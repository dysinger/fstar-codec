# Implementation Tasks: diagnose-pulse-hang

**Change**: root-cause and fix the `Data.Codec.Pulse` verification hang.

> ⚠️ **MANDATE (never forget):** only run `fstar.exe` / `nix build` / `make`
> wrapped in a **hard timeout**.  They hang forever (observed 35+ min at 0% CPU,
> `status = stopped`).  A stopped/0%-CPU process is *stuck*, not "working".
> Use `timeout 300 fstar.exe …` (macOS `gtimeout` or a `(sleep N && kill) &` guard).

## Phase 1 — Isolate the hanging query

- [ ] **T1 — Reproduce with a timeout + query log.**  Run `Data.Codec.Pulse`
      alone, with `--z3rlimit 120` and `--log_queries`, wrapped in
      `timeout 300`.  Capture the output (the last query emitted before it
      stalls becomes `queries-Data.Codec.Pulse.smt2` — gitignored).  Confirm:
      does it *hang* (no output, 0% CPU) or *time out* (clean `Error 19`
      "query timed out")?  These are different bugs.
- [ ] **T2 — Bisect the module.**  Comment out the roundtrip lemmas
      (`lemma_pulse_roundtrip_*` + `lemma_pulse_encode_decode_match`) and
      re-verify with a timeout.  If it terminates, the hang is in a lemma; if
      it still hangs, bisect the 8 encoders / 8 decoders / 2 dispatchers the
      same way (they are self-contained, so comment-and-recheck is fast).

## Phase 2 — Fix the hanging proof obligation

Candidates in priority order (each recorded from the earlier `--z3rlimit 80`
timeout + the shift→div change):

- [ ] **T3 — Per-`fn` rlimit.**  Wrap the hanging `fn` in
      `#push-options "--z3rlimit 400"` / `#pop-options` rather than raising the
      global limit.
- [ ] **T4 — Structural lemma.**  Lift the word32 byte-extraction arithmetic
      out of the post-condition into a standalone `Lemma` (head-normal form),
      mirroring the *old* `lemma_word32_shift_bytes` but for `U32.div`/`U32.rem`
      vs the pure `word32*.enc` division.
- [ ] **T5 — `noextract` helper predicate.**  Replace the inline
      `Seq.slice s1 == word32*.enc v` post-condition with a `noextract`
      predicate (as `varint_encode_pred` already does for varint), so SMT sees a
      named proposition instead of a big `Seq.equal`.
- [ ] **T6 — Query weight.**  If `--log_queries` shows one query with a huge
      term, add `--z3cliopt rlimit=…` or reduce the monomorphized obligation
      (e.g. avoid the 4-nested `Seq.append` in the `ensures`).

## Phase 3 — Re-verify the gate

- [ ] **T7 — `nix build .#fstar-codec-checked`** terminates and is GREEN
      (0-admit, spec + `Data.Codec.Pulse`).
- [ ] **T8 — `nix build .#fstar-codec-native`** terminates and produces
      `libfstar-codec.{dylib,so,a}` + `fstar_codec.h`.

## Unblocks

After this lands, resume **T3.2** (rewrite the two test modules to Pulse) and
**T3.3** (re-add them to `TST_MODS`) from
[`low-pulse-port`](../low-pulse-port/tasks.md).
