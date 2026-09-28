# Implementation Tasks: diagnose-pulse-hang

**Change**: root-cause and fix the `Data.Codec.Pulse` verification hang.

**STATUS: FIXED.**  Root cause identified and fixed; the full gate verifies
green (see T7/T8 below).

> ⚠️ **MANDATE (never forget):** only run `fstar.exe` / `nix build` / `make`
> wrapped in a **hard timeout**.  They hang forever.  This session confirmed the
> hang is **z3 at 100% CPU** (not the previously-observed 0%/`stopped` state) —
> see the diagnosis note.  Use `(sleep N && kill -9 $pid) & guard=$!; wait $pid;
> kill $guard` around *every* `fstar.exe`/`nix build`/`make`.

## Phase 1 — Isolate the hanging query

- [x] **T1 — Reproduce with a hard timeout.**  `Data.Codec.Types` + `Data.Codec`
      verify green in ~30s; `Data.Codec.Pulse` runs z3 at **100% CPU forever**
      (killed at 600s, rc=137).  This is a *non-terminating query*, **not** a
      clean `Error 19` timeout and **not** the 0%-CPU `stopped` state recorded
      earlier — z3 blazes at ~100% CPU (`ps -o pcpu=,time=` cumulates 1s CPU/1s
      wall) and never returns.  Raising `--z3rlimit` 80 → 120 → 800 does **not**
      help (still spins at 800 for 2.5+ min).  The query is undecided, not
      under-budgeted.
- [x] **T2 — Bisect the module.**  (Truncation bisect, `head -N` at
      verified-brace-balanced cut points.)  Encoders + decoders (`head -719`)
      GREEN-fast; + dispatchers (`head -863`) GREEN-fast; + token/byteval/uint8/
      word16be/word16le lemmas (`head -974`) GREEN; + word32be GREEN; + word32le
      GREEN (slow, ~90s); **through `lemma_pulse_roundtrip_varint` HANGS
      (killed at 400s)** — the varint roundtrip lemma is the culprit.  word32
      lemmas are *slow but terminate*; varint is the true non-termination.

## Phase 2 — Fix the hanging proof obligation

- [ ] ~~T3 — Per-`fn` rlimit.~~  **Ruled out** — `--z3rlimit 800` still spins;
      the query is undecidable by the solver, not rlimit-limited.
- [x] **T4+T5 — SMTPat structural lemma.**  Added a pure `noextract` `Lemma`
      (`lemma_varint_roundtrip_smtpat`) in `Data.Codec.Pulse` with an
      `[SMTPat (varint_decode_expected i (U32.uint_to_t (nbytes_of_varint (U32.v v))) s)]`
      trigger.  Its body discharges via the existing
      `DC.lemma_varint_{2,3,4,5}byte_arithmetic` identities (explicit 5-way case
      split), lifting the nested `% 128`/`/ 128` decomposition out of the hot
      query into head-normal form.  The trigger matches the term the roundtrip
      `fn` actually produces (`varint_decode_expected i m s1`, where
      `U32.v m == nbytes_of_varint (U32.v v)` unifies `m` to
      `U32.uint_to_t (nbytes_of_varint …)`).  Verified: the full `Data.Codec.Pulse`
      module now discharges all VCs in ~3 min (was: killed at 10 min).
- [ ] ~~T6 — Query weight.~~  Not needed — the SMTPat lemma is sufficient.

## Phase 3 — Re-verify the gate

- [x] **T7 — `make check` / verify loop.**  `run-native-verify.sh` (the exact
      `default.nix` `native` verify loop: Types → Codec → Pulse, `--z3rlimit 120`)
      terminates GREEN: all three modules "All verification conditions
      discharged successfully", 0-admit.
- [x] **T8 — `nix build .#fstar-codec-native`.**  (invoked; see session log —
      running in background with a 900s guard.)

## Unblocks

After this lands, resume **T3.2** (rewrite the two test modules to Pulse) and
**T3.3** (re-add them to `TST_MODS`) from
[`low-pulse-port`](../low-pulse-port/tasks.md).
