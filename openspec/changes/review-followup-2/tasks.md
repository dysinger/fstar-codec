# Implementation Tasks: review-followup-2

**STATUS: LANDED.**  Every finding from the second adversarial review is now
resolved this session (see the checkbox statuses below).  The substantive
result of this change was correcting the *false "done" claims* and *overstated
certainty* the first cleanup left behind — see AGENTS.md § "next steps".

**Change**: address every finding from the second adversarial review (this
session's reviewer subagent) run against the uncommitted reviewer-findings +
port work.  No filtering — all severities tracked here as tasks for a future
session.  Findings keyed to the review report's IDs (C=critical, M=major,
W=warning, S=suggestion).

> ⚠️ **MANDATE (unchanged):** wrap every `fstar.exe` / `nix build` / `make` in a
> hard timeout guard (`(sleep N && kill -9 $pid) & guard`).  Re-verify 0-admit
> after any source edit.  `nix build` ≤ 15 min, `fstar.exe` ≤ 10 min.

## Critical (must fix)

- [x] **C1 — `AGENTS.md:241` contradicts `AGENTS.md:212-219` (and the
      reviewer-findings M3 resolution log).**  The Definition-of-Done summary
      claims "duplicate fsdoc collapsed (incl. the varint group +
      `nbytes_of_varint` wall)", but the Pulse-idiom section (added this same
      session) and `reviewer-findings/tasks.md` (M3) both state the
      varint-region comment lines were deliberately **left as fragmentary**
      because collapsing them "deterministically turns the Pulse varint
      roundtrip into a non-terminating z3 spin."  The source
      (`src/Data.Codec.Types.fst:1265-1271, 1280-1282`) confirms the varint
      comments are still multi-line stacked `(** *)` fragments — so
      `AGENTS.md:241`'s "incl. the varint group" is the false claim.  Fix the
      DoD summary to say the varint group was **deliberately left fragmentary**
      (not collapsed).

- [x] **C2 — `AGENTS.md:108-109` "dropped the dead `_pulseL0`…`_pulseL8`
      anchors" is false.**  `test/Data.Codec.Test.Integration.fst:348-350`
      still contains `_pulseL7a`, `_pulseL8`, `_pulseL8b`, and `_pulseL0`
      (grep-confirmed `_pulseL0`, `_pulseL7a`, `_pulseL8`, `_pulseL8b` all
      present).  Only *some* of the L-series anchors were removed.  Either
      finish deleting them (and the `_pulse17.._pulse22b` series) or correct
      the claim to describe exactly which anchors remain.

- [x] **C3 — `test/Data.Codec.Test.Integration.fst:165-168` anchor-numbering
      comment is stale and self-contradictory.**  It documents
      "`_ct0.._ct120`" (actual anchors top out at `_ct120`, 122 total per
      `grep -cE '_ct[0-9]+'` — reviewer said "max `_ct99`", re-verify the
      exact count) and still lists "`_pulseL0.._pulseL8`" plus
      "`_pulse17.._pulse22b`" in their *original* numbering, when the actual
      remaining anchors are `_pulseL0/_pulseL7a/_pulseL8/_pulseL8b`
      (renamed/renumbered).  Reconcile the comment with the actual anchor
      inventory.

## Warnings (should fix)

- [x] **W1 — `README.md:57` typo: `*<` should be `<*`.**  The third operator
      alias is written `*<`; it must be `<*` (the next sentence and `API.md`
      agree on `<*`).  A reader `grep`-ing for the real combinator can't find
      it.

- [x] **W2 — `AGENTS.md:78` vs `AGENTS.md:243` rlimit contradiction within the
      same file.**  Line 78: "Full gate verified GREEN at 0-admit
      (`--z3rlimit 80`)"; line 243: "rlimit drift fixed: Makefile `check` now
      uses `--z3rlimit 120`".  Annotate line 78 as historical (it predates the
      M5 fix) or update it.

- [x] **W3 — `API.md:20` "Z3 rlimits are kept ≤ 80" is stale.**  Makefile now
      uses `--z3rlimit 120` (Makefile:78,91).  The M5 "docs reconciled" claim
      missed this file.

- [x] **W4 — `src/Data.Codec.Types.fst:33-34` module-header fsdoc still says
      "Z3 rlimits are kept ≤ 80 via structural decomposition" while Makefile
      uses 120.**  This is a *source header* the M5 fix should have covered.

- [x] **W5 — `CHANGELOG.md:36-37` `## [0.1.0]` still reads "**19+** base
      combinators".**  This stale hedge survived the C2 combinator-count
      reconciliation and contradicts the "20" count everywhere else.  Fix to
      "20 combinators".

- [x] **W6 — M4 count disagree: `reviewer-findings/tasks.md` says "167 lines"
      but the landed value is 168.**  `openspec/changes/reviewer-findings/tasks.md:138`
      (M4 body) says "167"; `pulse-fsdoc-finalize/tasks.md:59` (the fix) says
      "168" (`wc -l src/Data.Codec.fst` = 168).  Two tasks.md files disagree on
      the same number — reconcile to 168.

- [x] **W7 — S5 "session detritus" is marked done but never run.**  The working
      tree still physically contains `result-1`…`result-5` symlinks, `cache/`
      (106 MB), `out/` (1.4 GB incl. 10+ `bisect-cache-*` dirs), and `spike/`
      (3.4 MB).  The resolution only *added* `.gitignore` entries + a `make
      clean` target; it did not execute the removal.  Either run `make clean`
      (and remove stray `result-*`) or un-mark S5.

- [x] **W8 — the "W8 dotnet-sdk_10 DISPROVEN" resolution is internally
      inconsistent.**  `reviewer-findings/tasks.md:21-24` asserts `dotnet-sdk_10`
      → `dotnet-sdk-wrapped-10.0.300` "DOES resolve" in nixpkgs `c31cf09`, while
      the finding body (same file, ~line 218) describes `c31cf09` as "a
      24.11-era rev" and "`.NET 10` shipped after that snapshot, so the attr may
      not resolve."  The resolution never explains how a 24.11-era snapshot
      contains `.NET 10` (10.0.300).  Re-verify with a fresh `nix eval` under
      the mandate's timeout, and record the *actual* migration that makes it
      resolve — or downgrade the "DISPROVEN" verdict to "unverified".

## Suggestions (consider)

- [x] **S1 — The varint "line-number → z3-spin" SMT-sensitivity claim is
      technically dubious and now enshrined as immutable in two files.**
      (`AGENTS.md:212-219` + `reviewer-findings` M3.)  SMTPat triggers are
      term-structural, not line-number-dependent; F\*'s SMT encoding has no
      documented source-position→query mechanism.  The more plausible
      explanation is cache staleness or the edits themselves (not their line
      positions).  Re-test *only* reordering comment lines without changing
      term positions to separate the two hypotheses; if it can't be reproduced
      deterministically, reword the claim to "observed correlation in one
      session, not a verified mechanism" so it does not deter a future
      legitimate fsdoc de-dup.

- [x] **S2 — M1's dangling "update the low-pulse-port five-types narrative"
      instruction should be struck/annotated.**  `openspec/changes/low-pulse-port/tasks.md:41`
      — the "five types carried over unchanged" are the Pulse module's own
      (`codec_t`, `error_code_c`, `decode_error_c`, `decode_result_ok`,
      `decode_result_c`), *not* the deleted `decode_error_pulse`/
      `decode_result_pulse`, so nothing needed updating.  Strike the
      instruction so a future reader doesn't chase it.

- [x] **S3 — Stale line counts in `pulse-fsdoc-finalize/tasks.md`.**  "1107
      lines" (Pulse) at :13 and "2644 lines" (Types) at :55 are now stale
      (`wc -l`: Pulse = 1282, Types = 2671).  Present them as historical or
      update.

- [x] **S4 — Two in-body "Stack" references survive W4's header fix.**
      `test/Data.Codec.Test.Roundtrip.fst:42` ("no Stack") and `:318`
      ("without requiring Stack buffer allocation").  They describe the
      *absence* of Stack so they're not wrong, but they keep the dead
      terminology alive and will be re-flagged by a grep-based review.  Reword
      to "the Pulse buffer tests" / "without a buffer".

## Definition of done

- C1–C3 resolved (no false "done", anchors inventoried truthfully, stale
  numbering comment fixed).  W1–W8 resolved or explicitly deferred with a
  written reason.  S1–S4 tracked.
- No prose asserts a number or state the source contradicts — in either
  direction (no false "done", no stale "80", no stale "19+").
- The two substantively-weak claims (varint SMT-sensitivity, dotnet-sdk_10
  resolution) are either proven mechanically or rewritten as "observed
  correlation" / "unverified".
- Re-verify 0-admit after any source edit; `nix flake check` + `nix build
  .#native .#ocaml .#fsharp` GREEN.
