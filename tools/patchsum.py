#!/usr/bin/env python3
"""Patch byte 511 of a 512-byte boot sector so all bytes sum to 3 mod 256."""
import sys

path = sys.argv[1]
with open(path, 'rb') as f:
    data = bytearray(f.read())

assert len(data) == 512, f"Expected 512 bytes, got {len(data)}"

data[511] = (3 - sum(data[:511])) & 0xFF

assert sum(data) & 0xFF == 3
with open(path, 'wb') as f:
    f.write(data)

print(f"Patched {path}: byte 511 = 0x{data[511]:02X}, sector sum = 3")
