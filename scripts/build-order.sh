#!/bin/bash
# Prints the packages of this archive in an order that satisfies build-time
# dependencies between them, one per line:
#
#   scripts/build-order.sh resolute
#
# The order is derived, not declared. A package's debian/control already says
# what it produces (its Package: stanzas) and what it needs to build
# (Build-Depends), so an edge exists wherever one package's Build-Depends
# names a binary package another one produces. That is how an archive is
# meant to work -- Launchpad and OBS read the same two fields -- and a
# hand-written list beside it would be a second copy of the same fact.
#
# Reading control means having the source, so every package is fetched first.
# build-package.sh keeps what it fetched, keyed by REV, and reuses it for the
# real build rather than cloning a tree like ffmpeg's twice.

set -eE
trap 'echo "Error: in $0 on line $LINENO" >&2' ERR
cd "$(dirname "$0")/.."

SUITE="${1:?usage: $0 <suite>}"

for pkg in $(ls packages); do
    scripts/build-package.sh "${pkg}" "${SUITE}" --fetch-only >&2
done

SUITE="${SUITE}" python3 - <<'PY'
import os, pathlib, re, sys

suite = os.environ["SUITE"]
produces, needs = {}, {}
for d in sorted(pathlib.Path("packages").iterdir()):
    ctl = pathlib.Path("work") / suite / d.name / "src/debian/control"
    if not ctl.exists():
        sys.exit(f"Error: {d.name} has no {ctl}")
    # Comments are only legal in debian/control, so strip them before parsing.
    text = re.sub(r"(?m)^#.*\n", "", ctl.read_text(encoding="utf-8"))
    produces[d.name] = re.findall(r"(?m)^Package:\s*(\S+)", text)
    fields = re.findall(
        r"(?ms)^Build-Depends(?:-Arch|-Indep)?:\s*(.*?)(?=^\S+:|\Z)", text)
    # "pkg (>= 1) | other [arch]" -- only the first name of each alternative
    # can be relied on, and a version or arch qualifier is not part of it.
    needs[d.name] = [re.split(r"[ (|\[]", t.strip())[0]
                     for f in fields for t in f.split(",") if t.strip()]

owner = {b: p for p, bins in produces.items() for b in bins}
edges = {p: {owner[b] for b in bs if b in owner and owner[b] != p}
         for p, bs in needs.items()}

done, order = set(), []
while len(done) < len(edges):
    ready = sorted(p for p in edges if p not in done and edges[p] <= done)
    if not ready:
        left = sorted(set(edges) - done)
        sys.exit("Error: build-time dependency cycle among " + " ".join(left))
    order += ready
    done |= set(ready)
print("\n".join(order))
PY
