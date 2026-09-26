#!/usr/bin/env python3
"""
Differential fuzzing of atdcat: mutate the ATD files of the upstream
repository and compare the outputs of the MoonBit atdcat and of the
reference OCaml atdcat.

Usage:
  scripts/fuzz_atdcat.py <reference atdcat.exe> [count] [seed]
"""
import glob
import os
import random
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MBT = os.path.join(ROOT, "_build", "native", "debug", "build", "cmd",
                   "atdcat", "atdcat.exe")
TOKENS = ['(', ')', '[', ']', '{', '}', '<', '>', ';', ',', ':', '*', '|',
          '=', '?', '~', '.', 'from', 'import', 'as', 'type', 'of', 'inherit',
          'x', 'A', "'a", '"s"', "'q'", 'list', 'option', 'nullable',
          'shared', 'wrap', '(*', '*)', '\n', '"', '\\']
OPTIONS = [[], ["-x", "-i"]]


def run(exe, args):
    p = subprocess.run([exe] + args, capture_output=True)
    return p.stdout, p.stderr, p.returncode


def main():
    ref = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 1000
    random.seed(int(sys.argv[3]) if len(sys.argv) > 3 else 0)
    srcs = [open(f, encoding='latin-1').read() for f in
            glob.glob(os.path.join(ROOT, '.repos', 'atd', '**', '*.atd'),
                      recursive=True)]
    diffs = 0
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "fuzz.atd")
        for _ in range(count):
            parts = re.findall(r'\s+|\w+|"[^"]*"|.', random.choice(srcs))
            for _ in range(random.randint(1, 4)):
                if not parts:
                    break
                op = random.random()
                i = random.randrange(len(parts))
                if op < 0.4:
                    del parts[i]
                elif op < 0.8:
                    parts.insert(i, random.choice(['', ' ']) +
                                 random.choice(TOKENS) +
                                 random.choice(['', ' ']))
                else:
                    parts[i] = random.choice(TOKENS)
            src = ''.join(parts)
            with open(path, 'w', encoding='latin-1') as f:
                f.write(src)
            for opts in OPTIONS:
                if run(ref, opts + [path]) != run(MBT, opts + [path]):
                    diffs += 1
                    print("=== difference with options %s:\n%s" % (opts, src))
    print("%d differences" % diffs)
    sys.exit(1 if diffs else 0)


if __name__ == "__main__":
    main()
