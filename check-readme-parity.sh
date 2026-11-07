#!/usr/bin/env bash
# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# README structural-parity check (codec-audit-fixes T4b.4 / T5.4).
#
# Checks two things that a heading-only diff would miss:
#   1. the eight `##` sections match ../lean-codec/README.md in NAME and ORDER
#      (the trailing parentheticals legitimately differ — the two libraries use
#      different spec substrates, so only the part before " — " is compared);
#   2. no *substantive* content was lost: the anchor set is exactly the
#      expected [D1]-[D13] + [S1]-[S9] + [W1]-[W10] + [O1] (34 targets), and
#      the three blocks a past restructure silently deleted are present.
#
# (2) exists because commit 969d2d0 deleted three load-bearing blocks while its
# message claimed they had been "moved".  A restructure that only moves
# headings still deletes text.
#
# Usage: ./check-readme-parity.sh        (exit 0 = pass)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$HERE/README.md"
OTHER="$HERE/../lean-codec/README.md"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

[ -f "$README" ] || { echo "FAIL: no README.md at $README" >&2; exit 1; }

# ── 1. Headings: same names, same order ────────────────────────────────
if [ -f "$OTHER" ]; then
  grep '^## ' "$README" | sed 's/ —.*$//' > /tmp/rp_ours.txt
  grep '^## ' "$OTHER"  | sed 's/ —.*$//' > /tmp/rp_theirs.txt
  if ! diff -u /tmp/rp_theirs.txt /tmp/rp_ours.txt > /tmp/rp_diff.txt; then
    err "the eight ## headings do not match ../lean-codec/README.md in name/order:"
    sed 's/^/    /' /tmp/rp_diff.txt >&2
  else
    echo "ok: 8 ## headings match ../lean-codec/README.md in name and order"
  fi
else
  echo "skip: $OTHER not found, heading parity not checked" >&2
fi

# ── 2. Anchor set exactly as expected (nothing renumbered, nothing lost) ──
expected=""
for n in $(seq 1 13); do expected="$expected D$n"; done
for n in $(seq 1 9);  do expected="$expected S$n"; done
for n in $(seq 1 10); do expected="$expected W$n"; done
expected="$expected O1"

# definitions only: a definition is a line starting with **[X n]
grep -oE '^\*\*\[(D|S|W)[0-9]+\]|^\*\*\[O1\]' "$README" \
  | sed 's/^\*\*\[//; s/\]$//' | sort > /tmp/rp_defined.txt
printf '%s\n' $expected | sort > /tmp/rp_expected.txt

if ! diff -u /tmp/rp_expected.txt /tmp/rp_defined.txt > /tmp/rp_adiff.txt; then
  err "README anchor definitions differ from the expected set (renumbered, added or lost):"
  sed 's/^/    /' /tmp/rp_adiff.txt >&2
else
  echo "ok: all 33 anchors defined exactly once ([D1]-[D13], [S1]-[S9], [W1]-[W10], [O1])"
fi

# ── 3. The three blocks a restructure deleted must still be present ───────
check_block() {
  if grep -qF -- "$1" "$README"; then
    echo "ok: present — $1"
  else
    err "substantive content LOST — missing: $1"
  fi
}
check_block "What this library claims, and what it does not"
check_block "Not claimed"
check_block "decode_result_c"
check_block "separator family (\`sep_by1\`"

echo
if [ "$fail" = "0" ]; then echo "PASS: README structural parity"; else echo "FAILED"; fi
exit "$fail"
