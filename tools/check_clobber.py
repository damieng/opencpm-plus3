#!/usr/bin/env python3
"""
check_clobber.py — Static analysis for Z80 register clobbering bugs.

Parses .asm source files, extracts CALL targets, looks up their
documented "Clobbers:" lists, and flags any use of a clobbered
register after the CALL without an intervening restore.

Usage: python3 tools/check_clobber.py src/bios/*.asm src/bdos/*.asm src/ccp/*.asm
"""

import re
import sys
import os
from pathlib import Path

# Parse "Clobbers: AF, BC, DE, HL, IX" from comments
CLOBBER_RE = re.compile(r';\s*Clobbers?:\s*(.+)', re.IGNORECASE)
CALL_RE = re.compile(r'^\s*call\s+(\w+)', re.IGNORECASE)
PUSH_RE = re.compile(r'^\s*push\s+(\w+)', re.IGNORECASE)
POP_RE = re.compile(r'^\s*pop\s+(\w+)', re.IGNORECASE)
LABEL_RE = re.compile(r'^(\w[\w.]*):')
# Registers that read from a specific reg
READ_RE = {
    'A': re.compile(r'\b(ld\s+\([^)]+\),\s*a|ld\s+[^,]+,\s*a|or\s+a|and\s+a|cp\s+|add\s+a|sub\s+|out\s+\([^)]+\),\s*a|push\s+af)', re.I),
    'B': re.compile(r'\b(ld\s+[^,]+,\s*b(?!c)|djnz|push\s+bc)', re.I),
    'C': re.compile(r'\b(ld\s+[^,]+,\s*c\b|push\s+bc|out\s+\(c\))', re.I),
    'D': re.compile(r'\b(ld\s+[^,]+,\s*d(?!e)|push\s+de)', re.I),
    'E': re.compile(r'\b(ld\s+[^,]+,\s*e\b|push\s+de)', re.I),
    'H': re.compile(r'\b(ld\s+[^,]+,\s*h(?!l)|push\s+hl)', re.I),
    'L': re.compile(r'\b(ld\s+[^,]+,\s*l\b|push\s+hl)', re.I),
}

# Map register pair names to individual registers
PAIR_TO_REGS = {
    'AF': ['A'],
    'BC': ['B', 'C'],
    'DE': ['D', 'E'],
    'HL': ['H', 'L'],
    'IX': ['IX'],
    'IY': ['IY'],
}

def parse_clobber_list(text):
    """Parse 'AF, BC, DE, HL, IX' into set of individual register names."""
    regs = set()
    for part in text.split(','):
        part = part.strip().upper()
        # Remove anything in parens like "(none besides A)"
        part = re.sub(r'\(.*\)', '', part).strip()
        if part in PAIR_TO_REGS:
            regs.update(PAIR_TO_REGS[part])
        elif part in ('A', 'B', 'C', 'D', 'E', 'H', 'L', 'IX', 'IY'):
            regs.add(part)
    return regs


def extract_routine_clobbers(all_lines):
    """Build a dict: routine_name -> set of clobbered registers."""
    clobbers = {}
    current_routine = None

    for line in all_lines:
        # Check for label (routine start)
        m = LABEL_RE.match(line)
        if m:
            current_routine = m.group(1)

        # Check for Clobbers: comment
        m = CLOBBER_RE.search(line)
        if m and current_routine:
            regs = parse_clobber_list(m.group(1))
            if regs:
                clobbers[current_routine] = regs

    return clobbers


def check_file(filepath, routine_clobbers):
    """Check one file for register use after clobbering call."""
    issues = []

    with open(filepath) as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        # Look for CALL instructions
        m = CALL_RE.search(line)
        if not m:
            continue

        target = m.group(1)
        if target not in routine_clobbers:
            continue

        clobbered = routine_clobbers[target].copy()
        lineno = i + 1

        # Scan forward from the call, tracking which clobbered regs are restored
        restored = set()

        for j in range(i + 1, min(i + 20, len(lines))):  # Look ahead up to 20 lines
            fwd_line = lines[j].strip()

            # Skip comments and blank lines
            if not fwd_line or fwd_line.startswith(';'):
                continue

            # Check for POP that restores a clobbered register
            m_pop = POP_RE.match(fwd_line)
            if m_pop:
                pair = m_pop.group(1).upper()
                if pair in PAIR_TO_REGS:
                    restored.update(PAIR_TO_REGS[pair])
                continue

            # Check for LD that sets a register (partial restore)
            ld_match = re.match(r'\s*ld\s+([abcdehl]|ix|iy)\s*,', fwd_line, re.I)
            if ld_match:
                restored.add(ld_match.group(1).upper())

            # Check for label (end of basic block)
            if LABEL_RE.match(fwd_line):
                break

            # Check for RET/JP (end of flow)
            if re.match(r'\s*(ret|jp\s)', fwd_line, re.I):
                break

            # Check for CALL (another call — those registers are now live again)
            m_call2 = CALL_RE.match(fwd_line)
            if m_call2:
                break

            # Check if any clobbered (and not yet restored) register is READ
            for reg in (clobbered - restored):
                if reg in READ_RE and READ_RE[reg].search(fwd_line):
                    # Check it's not just being written to
                    write_match = re.match(r'\s*ld\s+' + reg.lower() + r'\s*,', fwd_line, re.I)
                    if not write_match:
                        issues.append({
                            'file': filepath,
                            'call_line': lineno,
                            'use_line': j + 1,
                            'target': target,
                            'register': reg,
                            'code': fwd_line.strip(),
                        })

    return issues


def main():
    if len(sys.argv) < 2:
        # Default: scan all our source files
        files = []
        for d in ['src/bios', 'src/bdos', 'src/ccp']:
            p = Path(d)
            if p.exists():
                files.extend(str(f) for f in p.glob('*.asm'))
    else:
        files = sys.argv[1:]

    # First pass: collect all lines to build routine clobber database
    all_lines = []
    for filepath in files:
        with open(filepath) as f:
            all_lines.extend(f.readlines())

    routine_clobbers = extract_routine_clobbers(all_lines)

    print(f"Known routine clobber lists ({len(routine_clobbers)} routines):")
    for name, regs in sorted(routine_clobbers.items()):
        print(f"  {name}: {', '.join(sorted(regs))}")
    print()

    # Second pass: check each file for issues
    total_issues = 0
    for filepath in files:
        issues = check_file(filepath, routine_clobbers)
        for issue in issues:
            print(f"WARNING: {issue['file']}:{issue['call_line']}: "
                  f"call {issue['target']} clobbers {issue['register']}, "
                  f"but line {issue['use_line']} reads it: {issue['code']}")
            total_issues += 1

    if total_issues == 0:
        print("No clobber issues found.")
    else:
        print(f"\n{total_issues} potential clobber issue(s) found.")

    return 1 if total_issues > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
