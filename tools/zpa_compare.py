#!/usr/bin/env python3
"""
zpa_compare.py — Diff ZPA preprocessor output against reference .asm files

Strips ZPA-generated housekeeping comments from both sides before diffing,
so you're comparing instruction semantics rather than formatting.

Usage
-----
  # Compare a single file pair
  python3 tools/zpa_compare.py build/zpa/bdos.asm reference/old/bdos/bdos.asm

  # Compare all .asm files in build/zpa/ against matching files under reference/old/
  python3 tools/zpa_compare.py build/zpa/ reference/old/ --all

  # Flat mode: reference dir has no sub-dirs (files sit directly in ref/)
  python3 tools/zpa_compare.py build/zpa/ reference/old/bdos/ --all --flat

Exit code: 0 if all identical, 1 if any differ or are missing.
"""

import sys
import re
import difflib
from pathlib import Path

# ---------------------------------------------------------------------------
# Normalisation
# ---------------------------------------------------------------------------

# Comments emitted by zpa.py that have no counterpart in the original source:
#   "; ── proc name"  "; ── extern name"
#   ";    param %x:u8 = b"  ";    var ..."  ";    out ..."  ";    clobbers ..."
#   "; call procname(args)"   (expansion annotation)
_ZPA_COMMENT = re.compile(
    r';\s*('
    r'──\s*(proc|extern)\s+\w+'   # proc/extern header
    r'|param\s+%'                  # param annotation
    r'|var\s+%'                    # var annotation
    r'|out\s+'                     # out annotation
    r'|clobbers\s+'                # clobbers annotation
    r'|call\s+\w+\('               # expanded call annotation
    r'|ZPA ERROR'                  # error markers (should not appear in clean output)
    r')'
)


def normalise(text: str) -> list[str]:
    """
    Return a normalised line list suitable for semantic comparison:
      - Drop ZPA-generated informational comments
      - Drop pure-comment lines and blank lines
      - Strip inline comments from code lines
      - Collapse runs of whitespace → single space, lowercase
    """
    out = []
    for raw in text.splitlines():
        stripped = raw.strip()

        # Skip blank lines
        if not stripped:
            continue

        # Skip pure-comment lines
        if stripped.startswith(';'):
            # But keep non-ZPA comments if you want — currently we drop all.
            # Change to `if not _ZPA_COMMENT.match(stripped): out.append(...)`
            # if you want to preserve intentional comments in the diff.
            continue

        # Strip inline comment
        code = raw.partition(';')[0].rstrip()
        if not code.strip():
            continue

        # Collapse whitespace, lowercase for case-insensitive compare
        normalised = re.sub(r'[ \t]+', ' ', code).strip().lower()
        out.append(normalised)

    return out


# ---------------------------------------------------------------------------
# File comparison
# ---------------------------------------------------------------------------

def compare(new_path: Path, ref_path: Path, verbose: bool = True) -> int:
    """
    Compare new_path (preprocessor output) against ref_path (reference).
    Returns 0 if identical after normalisation, 1 otherwise.
    """
    missing = False
    for p, label in ((new_path, 'generated'), (ref_path, 'reference')):
        if not p.exists():
            print(f"  MISSING {label}: {p}")
            missing = True
    if missing:
        return 1

    new_lines = normalise(new_path.read_text(encoding='utf-8'))
    ref_lines = normalise(ref_path.read_text(encoding='utf-8'))

    diff = list(difflib.unified_diff(
        ref_lines, new_lines,
        fromfile=f"ref:  {ref_path}",
        tofile=f"gen:  {new_path}",
        lineterm='',
        n=3,
    ))

    if not diff:
        if verbose:
            print(f"  OK    {new_path.name}")
        return 0

    # Count changed lines (ignore +++ / --- / @@ header lines)
    changed = sum(1 for l in diff if l and l[0] in ('+', '-')
                  and not l.startswith('---') and not l.startswith('+++'))
    print(f"  DIFF  {new_path.name}  ({changed} line(s) differ)")
    for line in diff:
        print(f"    {line}")
    return 1


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    import argparse

    ap = argparse.ArgumentParser(
        description='ZPA output vs reference .asm comparison tool')
    ap.add_argument('new', help='Preprocessor output file or directory')
    ap.add_argument('ref', help='Reference .asm file or directory')
    ap.add_argument('--all', action='store_true',
                    help='Compare every .asm file found under <new> dir')
    ap.add_argument('--flat', action='store_true',
                    help='Reference dir is flat (no subdirectories)')
    ap.add_argument('-q', '--quiet', action='store_true',
                    help='Only print files that differ')
    args = ap.parse_args()

    new_p = Path(args.new)
    ref_p = Path(args.ref)

    if new_p.is_file() and not args.all:
        sys.exit(compare(new_p, ref_p, verbose=not args.quiet))

    # Directory mode
    if not new_p.is_dir():
        print(f"ERROR: {new_p} is not a directory", file=sys.stderr)
        sys.exit(1)

    failures = 0
    checked  = 0
    for new_file in sorted(new_p.glob('**/*.asm')):
        if args.flat:
            ref_file = ref_p / new_file.name
        else:
            rel      = new_file.relative_to(new_p)
            ref_file = ref_p / rel

        # Try to find the reference file if flat search misses it
        if not ref_file.exists() and not args.flat:
            # Search recursively under ref_p for a file with the same name
            candidates = list(ref_p.rglob(new_file.name))
            if len(candidates) == 1:
                ref_file = candidates[0]

        failures += compare(new_file, ref_file, verbose=not args.quiet)
        checked  += 1

    print(f"\nzpa_compare: {checked} file(s) checked, {failures} differ")
    sys.exit(min(failures, 1))


if __name__ == '__main__':
    main()
