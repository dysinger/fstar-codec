# Change Proposal: review-followup-2

## Summary

Land every finding from the second, intentionally adversarial review of the
working-tree state (this session's reviewer subagent, run against the
uncommitted reviewer-findings cleanup + port work).  No filtering — all
severities are recorded as tasks for a future session.  Findings are keyed to
the review report's IDs (C=critical, M=major, W=warning, S=suggestion).

The headline is that the first cleanup session left **self-contradictions and
false "done" claims**: AGENTS.md asserts the varint fsdoc was *both* "collapsed"
and "deliberately left fragmentary"; dead `_pulseL*` anchors are declared
"dropped" but still exist; and the S5 "session detritus" cleanup is checked off
while 1.4 GB of `out/`, 106 MB `cache/`, and five `result-*` symlinks remain on
disk.

## Motivation

The repo's value proposition is "verified, 0-admit, mechanically-checkable
truth".  A fresh reviewer grep still finds prose that contradicts the source in
both directions (counts, rlimits, "done" markers), which is exactly the class of
deficiency the previous change was supposed to eliminate.  These are mechanical
doc/count/hygiene fixes — but they matter to anyone evaluating the repo, and
several of the claims now recorded as truth (the varint "line-number → z3-spin"
mechanism, the "dotnet-sdk_10 resolves to 10.0.300" DISPROVEN verdict) are
themselves weakly substantiated and deserve re-examination rather than being
enshrined as immutable constraints.

## Scope

- In scope: reconcile AGENTS.md/README/API.md/module-headers/CHANGELOG/openspec
  prose with the source (rlimit 80 vs 120, "19+" combinator count, stale anchor
  numbering, "collapsed" vs "left fragmentary" varint fsdoc), delete the
  remaining dead `_pulseL*`/`_pulse17.._pulse22b` anchors (or fix the claim),
  actually run the S5 detritus cleanup (or un-mark it), and re-examine the two
  weakest substantive claims (varint comment SMT-sensitivity; dotnet-sdk_10
  resolution) so they are either proven or rewritten as "observed correlation",
  not "deterministic mechanism".
- Out of scope: new combinators/backends, behavioral changes to the codecs,
  F\* formatter work (broken upstream), `../fstar` fork chores (push/LSP).

## Definition of done

- Every C/M/W finding resolved or explicitly deferred with a written reason;
  all S findings tracked.
- No prose (README/AGENTS/headers/CHANGELOG/openspec) asserts a number or state
  the source contradicts — in either direction (no false "done", no stale
  "80", no stale "19+").
- The varint SMT-sensitivity claim is either proven mechanically or reworded to
  "observed correlation in one session" (not "deterministic line-number
  mechanism"); same bar for the dotnet-sdk_10 DISPROVEN verdict.
- Source still 0-admit; `nix flake check` + `nix build .#native .#ocaml .#fsharp`
  GREEN (re-verified after any source edit, with the hard-timeout mandate).
