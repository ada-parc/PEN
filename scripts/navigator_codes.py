#!/usr/bin/env python3
"""Make navigator codes and their personal links.

    python3 -I scripts/navigator_codes.py 1 50 > navigator-codes.csv
    python3 -I scripts/navigator_codes.py 0 0          # the test code, N-000-0

Prints a CSV (number, code, link) for every navigator number in the range.
A code is "N-", the three-digit number, and one Damm check digit, the same
rule assets/navigator-init.html checks, so a typed or copied code with one
wrong digit or two swapped neighbouring digits is refused instead of being
recorded under someone else's number.

The list is a roster, not site content: keep it out of the repo
(navigator-codes*.csv is gitignored).
"""
import csv
import sys

SITE = "https://ada-parc.github.io/PEN/"

DAMM = [
    [0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
    [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
    [4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
    [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
    [6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
    [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
    [5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
    [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
    [9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
    [2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
]


def damm(digits):
    interim = 0
    for d in digits:
        interim = DAMM[interim][int(d)]
    return interim


def code_for(number):
    digits = f"{number:03d}"
    return f"N-{digits}-{damm(digits)}"


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    first, last = int(argv[1]), int(argv[2])
    if not 0 <= first <= last <= 999:
        sys.exit("Numbers must be 0 to 999, first <= last.")
    out = csv.writer(sys.stdout, lineterminator="\n")
    out.writerow(["number", "code", "link"])
    for n in range(first, last + 1):
        code = code_for(n)
        out.writerow([n, code, f"{SITE}?nav={code}"])


if __name__ == "__main__":
    main(sys.argv)
