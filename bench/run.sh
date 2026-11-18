#!/usr/bin/env bash
# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# bench/run.sh — build and run the codec benchmark, post- vs pre-tightening.
#
# Usage (from the fstar-codec repo root, inside the dev shell):
#
#   nix develop -c ./bench/run.sh
#
# It does four things, in order:
#
#   1. extracts the C for HEAD                     -> $WORK/post
#   2. extracts the C for the commit BEFORE the     -> $WORK/pre
#      canonicalisation guard (default: 32aa8e8^)
#   3. compiles and runs bench-pulse (extracted C) and bench-ref (hand-written
#      C baseline) for BOTH, and
#   4. prints a table: ps/op for each row, baseline vs extracted, and the
#      post-vs-pre delta on the varint decode row (the T9.2 question).
#
# The extraction recipes are the two that are known to work on this host (see
# AGENTS.md and research.md F80); `nix build .#native` is NOT used because it
# re-verifies from cold and has been observed to hang.
#
# Every step is checked; the script exits non-zero if any of them fails.  It is
# deliberately not silent: a benchmark that "passes" without printing is not
# evidence.

set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
pre_rev="${PRE_REV:-32aa8e8^}"
rounds="${BENCH_ROUNDS:-41}"
work="${WORK:-$(mktemp -d)}"
trap 'echo "work dir: $work"' EXIT
mkdir -p "$work/post" "$work/pre"

: "${FSTAR_CHECKED:?FSTAR_CHECKED is not set; run inside the dev shell}"

echo "== repo:    $here"
echo "== head:    $(git -C "$here" rev-parse --short HEAD)"
echo "== pre-rev: $pre_rev ($(git -C "$here" rev-parse --short "$pre_rev"))"
echo "== rounds:  $rounds"
echo "== work:    $work"
echo

# ── 1. Extract both sides ───────────────────────────────────────────

# extract <src-dir> <out-dir>
#
# Two fstar.exe runs per module, in dependency order, into ONE cache dir: verify
# first, then extract reading that cache.  A single invocation cannot do both —
# error 317 "Cross-module inlining expects all modules to be checked first"
# appears because `src/Data.Codec` needs `Data.Codec.Types`'s `.checked` file
# before `Data.Codec.Pulse` can inline against it.
extract() {
    local src="$1" out="$2"
    local flib
    flib="$(fstar.exe --locate_lib)"
    mkdir -p "$out/cache"
    cp "$FSTAR_CHECKED"/*.checked "$out/cache/" 2>/dev/null || true
    local incs=(--no_default_includes --include "$flib/ulib"
        --include "$flib/pulse/common" --include "$flib/pulse/common.checked"
        --include "$flib/pulse/pulse/lib" --include "$flib/pulse/pulse.checked")
    (
      cd "$src"
      for m in Data.Codec.Types Data.Codec.Text Data.Codec Data.Codec.Pulse; do
          fstar.exe "${incs[@]}" --include ./src \
              --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
              --z3rlimit 120 \
              --cache_checked_modules --cache_dir "$out/cache" --odir "$out/cache" \
              "src/$m.fst"
      done
      fstar.exe "${incs[@]}" --include ./src --include "$out/cache" \
          --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
          --cache_checked_modules --cache_dir "$out/cache" \
          --codegen C --custard_monomorphize_types true \
          --custard_entry_module Data.Codec.Pulse \
          --custard_c_no_prefix Data.Codec.Pulse \
          --odir "$out" src/Data.Codec.Pulse.fst
    ) > "$out/extract.log" 2>&1 \
      || { echo "extraction FAILED ($out); see $out/extract.log"; tail -20 "$out/extract.log"; exit 1; }
    cp "$out/Custard.h" "$out/codec.h"
    echo "extracted -> $out ($(wc -l < "$out/Custard.c") lines of C)"
}

echo "-- extracting HEAD --"
extract "$here" "$work/post"

echo "-- extracting $pre_rev --"
if [ -d "$work/pre-src" ]; then rm -rf "$work/pre-src"; fi
git -C "$here" worktree add --detach "$work/pre-src" "$pre_rev" > /dev/null 2>&1
extract "$work/pre-src" "$work/pre"
git -C "$here" worktree remove --force "$work/pre-src" > /dev/null

# The two extractions must differ, and differ ONLY at the guard.  If they are
# identical the comparison below measures noise and claims a delta of zero.
if cmp -s "$work/pre/Custard.c" "$work/post/Custard.c"; then
    echo "ERROR: pre and post C are identical — the guard did not reach the C"
    exit 1
fi
echo "-- diff pre->post: $(diff "$work/pre/Custard.c" "$work/post/Custard.c" | grep -c '^[<>]') changed lines (expected: the guard) --"
echo

# ── 2. Build the four binaries ──────────────────────────────────────

cc_common="-O2 -std=c11 -Wall -Wextra -Werror -DBENCH_ROUNDS=$rounds"

build() {
    local out="$1" def="$2"
    cc $cc_common $def -o "$work/bench-ref"      "$here/bench/bench-ref.c"
    cc $cc_common $def -I "$work/post" -o "$work/bench-pulse-post" "$here/bench/bench-pulse.c" "$work/post/Custard.c"
    cc $cc_common $def -I "$work/pre"  -o "$work/bench-pulse-pre"  "$here/bench/bench-pulse.c" "$work/pre/Custard.c"
}

echo "-- building --"
build "$work" ""
echo

# ── 3. Run and tabulate ─────────────────────────────────────────────

# Run each binary BENCH_RUNS times, ALTERNATING pre/post so a load spike hits
# both equally, and keep the per-row MINIMUM (best_ps, column 3).  On a shared
# machine the minimum is the least contaminated estimator: noise only ever adds
# time, so the fastest observed round is the closest to the true cost.  The
# median is kept in the raw files; the table uses the min.
runs="${BENCH_RUNS:-5}"
rm -f "$work"/{ref,post,pre}.tsv "$work"/{ref,post,pre}.err
for i in $(seq 1 "$runs"); do
    "$work/bench-ref"         >> "$work/ref.tsv"  2>>"$work/ref.err"
    "$work/bench-pulse-pre"   >> "$work/pre.tsv"  2>>"$work/pre.err"
    "$work/bench-pulse-post"  >> "$work/post.tsv" 2>>"$work/post.err"
    echo "  run $i/$runs done"
done

# The roundtrip self-check both drivers run must have passed.
for e in ref post pre; do
    grep -q 'roundtrip OK' "$work/$e.err" || { echo "ERROR: $e self-check FAILED"; cat "$work/$e.err"; exit 1; }
done
echo "-- all three binaries passed their roundtrip self-check --"

# Every row must be resolved (0 unresolved rounds) and the sinks must agree:
# the same bytes in must produce the same values out, or the comparison is
# between two different programs.
sink_of() { grep -o 'sink=[0-9]*' "$1"; }
[ "$(sink_of "$work/ref.err")" = "$(sink_of "$work/post.err")" ] \
    || { echo "ERROR: baseline and extracted disagree on the sink"; exit 1; }
[ "$(sink_of "$work/pre.err")" = "$(sink_of "$work/post.err")" ] \
    || { echo "ERROR: pre and post disagree on the sink (behaviour changed, not just cost)"; exit 1; }
for t in ref post pre; do
    if awk -F'\t' '!/^#/ && $4 != 0 { exit 1 }' "$work/$t.tsv"; then :; else
        echo "ERROR: $t has unresolved rounds (a number that came from rounding)"; exit 1
    fi
done
echo "-- sinks agree across all three; every round resolved --"
echo

python3 - "$work" <<'PY'
import sys, os
work = sys.argv[1]
def load(p):
    """Per row, the MINIMUM best_ps over all runs (column 3)."""
    out = {}
    for line in open(p):
        if line.startswith('#'): continue
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 3: continue
        v = int(parts[2])
        if v == 0: continue
        if parts[0] not in out or v < out[parts[0]]:
            out[parts[0]] = v
    return out
ref, pre, post = load(f"{work}/ref.tsv"), load(f"{work}/pre.tsv"), load(f"{work}/post.tsv")
rows = [r for r in post if r in ref and r in pre]
w = max(len(r) for r in rows)
print(f"{'row (best ps/op over all runs)':<{w}}  {'baseline':>9}  {'extracted':>9}  {'post/base':>9}")
print("-" * (w + 34))
for r in rows:
    ratio = post[r] / ref[r] if ref[r] else float('nan')
    print(f"{r:<{w}}  {ref[r]:>9}  {post[r]:>9}  {ratio:>8.2f}x")
print()
key = next((r for r in rows if r.startswith('decode/varint')), None)
if key:
    dp, dq = post[key] - pre[key], pre[key]
    print(f"T9.2 — canonicalisation cost on {key}:")
    print(f"  pre-tightening   {pre[key]:>7} ps/op")
    print(f"  post-tightening  {post[key]:>7} ps/op")
    print(f"  delta            {dp:>+7} ps/op  ({100*dp/dq:+.1f}%)")
else:
    print("WARNING: decode/varint row missing — T9.2 not measured")
PY
