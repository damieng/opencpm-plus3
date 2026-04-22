#!/usr/bin/env python3
"""Fail the build if the BIOS memory layout violates known invariants.

Runs after `build_memory_map.py` has parsed `build/bios.lst`. Checks that:

  - The system bank 4 image fits in 16 KB.
  - The common memory stub fits within FA00..FFFF.
  - Critical sized buffers have the expected byte count.
  - Critical buffers sit inside the common memory range.
  - The CPM3.SYS file (C000..common_image_end) stays below 0x10000.

These invariants are already asserted by sjasmplus at assembly time for the
sizes that are statically known. This checker gives us a single place to look
when something drifts, and can flag tight slack before it becomes a bug.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from build_memory_map import Label, Section, parse_listing


class LayoutError(Exception):
    pass


def _labels_by_name(sections: list[Section]) -> dict[str, Label]:
    out: dict[str, Label] = {}
    for s in sections:
        for lbl in s.labels:
            out[lbl.name] = lbl
    return out


def _require(labels: dict[str, Label], name: str) -> Label:
    if name not in labels:
        raise LayoutError(f"missing expected label: {name}")
    return labels[name]


def _size_between(labels: dict[str, Label], start: str, end: str) -> int:
    a = _require(labels, start)
    b = _require(labels, end)
    return b.addr - a.addr


def _find_label_after(section: Section, lbl: Label) -> Label | None:
    ordered = sorted(section.labels, key=lambda l: l.addr)
    for i, x in enumerate(ordered):
        if x is lbl:
            return ordered[i + 1] if i + 1 < len(ordered) else None
    return None


def check(sections: list[Section]) -> list[str]:
    errors: list[str] = []
    labels = _labels_by_name(sections)
    file_section, system_section, common_section = sections

    # --- Section fit ---------------------------------------------------------
    system_end = labels.get("system_end")
    if system_end and system_end.addr > system_section.limit:
        errors.append(
            f"system_end 0x{system_end.addr:04X} exceeds bank 4 limit 0x{system_section.limit:04X}")

    common_end = labels.get("common_end")
    if common_end and common_end.addr > 0x10000:
        errors.append(f"common_end 0x{common_end.addr:04X} exceeds 0xFFFF")

    common_image_end = labels.get("common_image_end")
    if common_image_end and common_image_end.addr > 0x10000:
        errors.append(
            f"common_image_end 0x{common_image_end.addr:04X} — CPM3.SYS overflows bank 3 window")

    # --- Buffer sizes (expected fixed layout) --------------------------------
    expected_sizes = [
        # (start_label, end_label, expected_bytes, description)
        ("dirbuf",         "fcb_buf",          128, "directory buffer"),
        ("fcb_buf",        "fcb_user_addr",     36, "FCB shadow buffer"),
        ("xfer_staging",   "bdos_stack_base",   32, "inter-bank transfer staging"),
        ("bdos_stack_base","bdos_stack",        64, "BDOS stack"),
        ("xdpb_a",         "xdpb_b",            27, "xdpb_a"),
    ]
    for start, end, want, desc in expected_sizes:
        if start not in labels or end not in labels:
            continue
        got = _size_between(labels, start, end)
        if got != want:
            errors.append(
                f"{desc}: {start}..{end} = {got} bytes, expected {want}")

    # xdpb_b has no adjacent sibling label; compare against dirbuf (next in map).
    if "xdpb_b" in labels and "dirbuf" in labels:
        got = labels["dirbuf"].addr - labels["xdpb_b"].addr
        if got != 27:
            errors.append(f"xdpb_b..dirbuf = {got} bytes, expected 27")

    # --- Buffers must sit inside common memory range -------------------------
    for name in ("dirbuf", "fcb_buf", "xfer_staging",
                 "bdos_stack_base", "bdos_stack",
                 "xdpb_a", "xdpb_b", "xdph_a", "xdph_b"):
        lbl = labels.get(name)
        if lbl and not (0xFA00 <= lbl.addr < 0x10000):
            errors.append(f"{name} at 0x{lbl.addr:04X} — expected inside common memory (FA00..FFFF)")

    return errors


def summary(sections: list[Section]) -> list[str]:
    rows: list[str] = []
    labels = _labels_by_name(sections)
    file_section, system_section, common_section = sections

    def _pct(used: int, total: int) -> str:
        return f"{used} / {total} bytes ({100.0 * used / total:.1f}%)"

    if "system_end" in labels:
        used = labels["system_end"].addr - system_section.base
        rows.append(f"  bank 4 used: {_pct(used, system_section.limit - system_section.base)}")
    if "common_end" in labels:
        used = labels["common_end"].addr - common_section.base
        rows.append(f"  common used: {_pct(used, 0x10000 - common_section.base)}")
    if "common_image_end" in labels:
        size = labels["common_image_end"].addr - file_section.base
        rows.append(f"  CPM3.SYS image: {size} bytes (C000..{labels['common_image_end'].addr:04X})")
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lst", default="build/bios.lst", type=Path)
    args = parser.parse_args(argv)

    if not args.lst.exists():
        print(f"error: listing not found: {args.lst}", file=sys.stderr)
        return 2

    sections = parse_listing(args.lst)
    errors = check(sections)

    for row in summary(sections):
        print(row)

    if errors:
        print("  layout errors:", file=sys.stderr)
        for e in errors:
            print(f"    - {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
