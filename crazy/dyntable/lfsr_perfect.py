#!/usr/bin/env python3
"""
Find a Galois LFSR (i.e. a CRC) of width <= 64 that maps every string in a
list to a distinct register state.

Usage:
    python3 lfsr_perfect.py strings.txt            # one string per line
    python3 lfsr_perfect.py strings.txt --min-width 32 --max-width 64
"""

import argparse
import random
import sys

# Known-good default: CRC-64/XZ (ECMA-182), x^64 + x^62 + ... + 1
DEFAULT_POLY_64 = 0x42F0E1EBA9EA3693


def make_table(poly, width):
    """Byte-wise MSB-first CRC table. `poly` omits the implicit x^width term."""
    assert 8 <= width <= 64
    mask = (1 << width) - 1
    top = 1 << (width - 1)
    table = []
    for b in range(256):
        r = (b << (width - 8)) & mask
        for _ in range(8):
            r = ((r << 1) ^ poly) & mask if r & top else (r << 1) & mask
        table.append(r)
    return table


def make_crc(poly, width, init=None):
    """Return a function data->state. init defaults to all-ones."""
    table = make_table(poly, width)
    mask = (1 << width) - 1
    shift = width - 8
    init = mask if init is None else init

    def crc(data):
        r = init
        for byte in data:
            r = ((r << 8) & mask) ^ table[((r >> shift) ^ byte) & 0xFF]
        return r

    return crc


def collisions(data, crc):
    """Return a list of (state, [strings]) for every colliding state."""
    seen = {}
    for d in data:
        seen.setdefault(crc(d), []).append(d)
    return [(v, ds) for v, ds in seen.items() if len(ds) > 1]


def search(data, width, trials=64, seed=0, first_poly=None):
    """Try polynomials of the given width until one is injective."""
    rng = random.Random(seed)
    for t in range(trials):
        if t == 0 and first_poly is not None:
            poly = first_poly
        else:
            # constant term must be 1, and the high bit is implicit
            poly = rng.getrandbits(width) | 1
        c = make_crc(poly, width)
        if len(set(c(d) for d in data)) == len(data):
            return poly, t + 1
    return None, trials


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--min-width", type=int, default=24)
    ap.add_argument("--max-width", type=int, default=64)
    ap.add_argument("--trials", type=int, default=64)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    with open(args.path, "rb") as f:
        data = [line.rstrip(b"\r\n") for line in f]
    data = [d for d in data if d]
    n = len(data)
    if len(set(data)) != n:
        sys.exit("Input contains duplicate strings; dedupe first.")
    print(f"{n} distinct strings loaded")

    # Walk down from max_width to find the smallest width that works.
    best = None
    for width in range(args.max_width, args.min_width - 1, -1):
        first = DEFAULT_POLY_64 if width == 64 else None
        poly, used = search(data, width, args.trials, args.seed, first)
        if poly is None:
            print(f"width {width}: no injective polynomial in {used} trials")
            break
        best = (width, poly)
        print(f"width {width}: OK  poly=0x{poly:0{(width + 3) // 4}X} "
              f"(found on trial {used})")

    if best:
        width, poly = best
        print(f"\nUse a {width}-bit register, feedback polynomial "
              f"0x{poly:0{(width + 3) // 4}X}, init = all ones, "
              f"bytes fed MSB-first.")


if __name__ == "__main__":
    main()
