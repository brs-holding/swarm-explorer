#!/usr/bin/env python3
"""Prove that a built release carries none of upstream's development secrets.

Why this is not a grep
----------------------

A release's ``sys.config`` holds Erlang terms, and a binary in one may be
written either as ``<<"secret">>`` or as a list of byte values, wrapped across
lines by the term printer::

    {signing_salt,<<115,101,99,114,
                    101,116>>}

A grep for the value over the second form finds nothing, which reads like
evidence of absence and is not.  Workstream F hit exactly that while checking
image ``brs-swarm-explorer:7834a2232fd6``.  This script decodes every byte
sequence it finds, in either form, and compares as **bytes**.

(The example above spells "secret".  No real value is written in this file;
the values being looked for live in the denylist, once.)

Usage
-----

    ci/check-release-secrets.py [--denylist FILE] [--forbid-key KEY]... PATH...
    ci/check-release-secrets.py --self-test

``PATH`` may be a file or a directory (walked recursively).  Exit status is 0
when nothing forbidden is present, 1 when something is, 2 on a usage error.

``--forbid-key`` additionally fails when an Erlang key appears at all, which is
the stronger statement for ``sys.config``: after the fix no Phoenix secret is
compile-time configuration, so the key itself should be absent whatever its
value.

The denylist holds upstream's published development values, not live secrets;
nothing this script prints can leak one, because a match is reported by the
denylist's line number and never by its content.
"""

import argparse
import os
import re
import sys

DEFAULT_DENYLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "upstream-dev-secrets.txt")

# Every run of digits, commas and whitespace, whatever encloses it: `<<97,52>>`
# and `[97,52]` are Erlang's two spellings and the term printer wraps either
# across lines. Matching the run rather than its delimiters keeps this a single
# linear pass with no backtracking, which matters when the target is a whole
# release tree rather than one config file.
BYTE_RUN = re.compile(rb"[0-9][0-9,\s]*[0-9]")


def load_denylist(path):
    """[(line number, value bytes)] from a denylist file."""
    entries = []
    with open(path, "rb") as handle:
        for number, line in enumerate(handle, start=1):
            value = line.strip()
            if not value or value.startswith(b"#"):
                continue
            entries.append((number, value))
    if not entries:
        raise SystemExit("denylist %s lists nothing; refusing to pass "
                         "vacuously" % path)
    return entries


def decoded_runs(blob):
    """Every Erlang byte run in ``blob``, decoded to bytes."""
    for match in BYTE_RUN.finditer(blob):
        pieces = [piece.strip() for piece in match.group(0).split(b",")]
        if len(pieces) < 2:
            continue
        if not all(piece.isdigit() and int(piece) <= 255 for piece in pieces):
            continue
        yield bytes(int(piece) for piece in pieces)


def scan(blob, denylist):
    """[(line number, how it was found)] for every denylist hit in ``blob``."""
    runs = list(decoded_runs(blob))
    hits = []
    for number, value in denylist:
        if value in blob:
            hits.append((number, "present verbatim"))
        elif any(value in run for run in runs):
            hits.append((number, "present as an Erlang byte run "
                                 "(a literal grep would have missed it)"))
    return hits


def scan_keys(blob, keys):
    return [key for key in keys if re.search(rb"\b" + re.escape(key) + rb"\b", blob)]


def files_under(path):
    if os.path.isfile(path):
        return [path]
    found = []
    for root, _dirs, names in os.walk(path):
        for name in names:
            found.append(os.path.join(root, name))
    return sorted(found)


def check(paths, denylist, forbidden_keys):
    failed = False
    checked = 0

    for path in paths:
        for target in files_under(path):
            with open(target, "rb") as handle:
                blob = handle.read()
            checked += 1

            for number, how in scan(blob, denylist):
                failed = True
                print("FAIL  %s carries denylist entry on line %d: %s"
                      % (target, number, how))

            for key in scan_keys(blob, forbidden_keys):
                failed = True
                print("FAIL  %s still sets %s at build time; it must come "
                      "from the environment at boot"
                      % (target, key.decode()))

    if checked == 0:
        print("FAIL  nothing was checked; the path is wrong")
        return False

    if not failed:
        print("ok    %d file(s) checked, %d denylist entr(ies), no match"
              % (checked, len(denylist)))
    return not failed


# ---------------------------------------------------------------------------
# Self-test: the byte comparison is the whole point, so it is proven before it
# is trusted.
# ---------------------------------------------------------------------------

def as_byte_run(value, per_line=20):
    """The way Erlang's term printer wraps a long binary, worst case."""
    numbers = [str(byte) for byte in value]
    lines = [",".join(numbers[i:i + per_line])
             for i in range(0, len(numbers), per_line)]
    return b"<<" + b",\n                   ".join(
        line.encode() for line in lines) + b">>"


def self_test():
    # The fixture is the real denylist's first entry, so the literal lives in
    # exactly one place in this repository.
    number, salt = load_denylist(DEFAULT_DENYLIST)[0]
    denylist = [(number, salt)]
    failures = []

    def expect(condition, description):
        print(("ok    " if condition else "FAIL  ") + description)
        if not condition:
            failures.append(description)

    wrapped = b"{signing_salt," + as_byte_run(salt) + b"}"

    expect(salt[:6] not in wrapped,
           "the byte-run form really does defeat a literal grep")
    expect(len(scan(wrapped, denylist)) == 1,
           "the byte-run form is caught")
    expect(len(scan(b'{signing_salt,<<"' + salt + b'">>}', denylist)) == 1,
           "the verbatim form is caught")
    expect(len(scan(b"{signing_salt,[" +
                    b",".join(str(b).encode() for b in salt) + b"]}",
                    denylist)) == 1,
           "the charlist form is caught")
    expect(scan(b'{live_view,[{signing_salt,<<"SomethingElse">>}]}',
                denylist) == [],
           "an unrelated value is not a false positive")
    expect(scan_keys(b"{url,[{host,<<\"localhost\">>}]}",
                     [b"secret_key_base", b"signing_salt"]) == [],
           "a clean sys.config trips no key rule")
    expect(scan_keys(b"{secret_key_base,<<\"x\">>}", [b"secret_key_base"]) ==
           [b"secret_key_base"],
           "a compile-time secret_key_base trips the key rule")

    if failures:
        print("\n%d self-test check(s) failed" % len(failures))
        return False
    print("\nself-test passed")
    return True


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", metavar="PATH")
    parser.add_argument("--denylist", default=DEFAULT_DENYLIST)
    parser.add_argument("--forbid-key", action="append", default=[],
                        metavar="KEY")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return 0 if self_test() else 1

    if not args.paths:
        parser.print_usage()
        return 2

    denylist = load_denylist(args.denylist)
    keys = [key.encode() for key in args.forbid_key]
    return 0 if check(args.paths, denylist, keys) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
