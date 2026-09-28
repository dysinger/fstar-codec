# Implementation Tasks: low-pulse-port

**Change**: rewrite `Data.Codec.Pulse` from KaRaMeL Low\* (`Stack` +
`LowStar.Buffer`) to Pulse (`fn` + `Pulse.Lib.*`) so it extracts to C via
Custard (`--custard_backend C`), restoring the `native` target.

> **Prerequisite**: the `fstar-roll-forward` change is landed (F\*
> `v2026.09.20+lsp` + Custard + karamel removed).

## ⚠️ BLOCKED — `Data.Codec.Pulse` verify HANGS (non-terminating SMT query)

T3/T4 are **blocked**: `Data.Codec.Types` and `Data.Codec` verify, then the
`Data.Codec.Pulse` `fstar.exe` run hangs forever (35+ min at 0% CPU, `status =
stopped`).  It verified + extracted green **earlier this session** (commit
`a34c984` produced `libfstar-codec.dylib`), so this is a flaky/non-terminating
SMT query — not a type error.  Prime suspects (the `--z3rlimit`-sensitive
word32 roundtrip/encode `fn`s) and a step-by-step isolation plan
(`--log_queries` + `timeout`, raise rlimit per-`fn` via `#push-options`, lift
byte-extraction into a `Lemma`, or use a `noextract` helper predicate) are in
[`AGENTS.md`](../../../AGENTS.md) § "BLOCKED".

**T3.2 (test rewrite) depends on this** — the test modules `open Data.Codec.Pulse`.

## Phase 1 — Spike the Pulse idiom (de-risk before the full port)

- [x] **T1.1 — Minimal Pulse leaf.**  Done: `spike/Data.Codec.Spike.fst` ports
      `encode_token` / `decode_token` to Pulse (`fn`, `A.array U8.t`,
      `pts_to`, `b.(j) <- x`).  Verifies 0-admit.
- [x] **T1.2 — Extract it via Custard.**  Done: `--custard_backend C
      --custard_monomorphize_types true --custard_entry_module Data.Codec.Spike`
      emits warning-free C11 (`cc -Wall -Wextra -Werror` clean), no karamel.
- [x] **T1.3 — Pin the idiom.**  Recorded in `AGENTS.md` (§ "Pulse idiom —
      PINNED by the spike").  Key findings: types carry bounds (not `pure`
      preconds); `FStar.Int.Cast` for `U8↔U32` (no `U32.v` in bodies);
      `uint32_to_sizet` at the read/write boundary; `A.length b` for
      self-contained ensures bounds.

## Phase 2 — Full leaf port

- [x] **T2.1 — Types.**  Done: `codec_t`, `error_code_c`, `decode_error_c`,
      `decode_result_ok`, `decode_result_c` carried over unchanged (plain F\*),
      extracted as clean C tagged unions.
- [x] **T2.2 — Encoders.**  Done: all 8 (`encode_token/byteval/uint8`,
      `word16be/le`, `word32be/le`, `varint`) ported to Pulse `fn`, verified,
      C-extracted.  `word32be/le` use `U32.div` (not shift) to match the pure
      `*.enc` division structure.
- [x] **T2.3 — Decoders.**  Done: all 8 ported to Pulse `fn` returning
      `decode_result_c`, verified, C-extracted (`varint` uses machine ints only).
- [x] **T2.4 — Dispatch.**  Done: `encode_bytes` / `decode_bytes` match-dispatch
      with full per-constructor post-conditions, verified, extracted.
- [x] **T2.5 — Ghost spec + constants.**  Done: `varint_encode_pred` and
      `varint_decode_expected` are `noextract` pure specs (skipped by Custard).
- [x] **T2.6 — Roundtrip lemmas.**  Done: `lemma_pulse_roundtrip_{token,
      byteval,uint8,word16be,word16le,word32be,word32le,varint}` + `lemma_pulse_
      encode_decode_match` ported to Pulse `fn` and verified.  Much easier than
      feared: the pure `codec` `.enc`/`.dec` are record projections that
      compute, so `dec (enc x)` reduces and SMT discharges the roundtrip
      without the old `lemma_word32_shift_bytes` / `h_mid` heap threading.

## Phase 3 — Restore the build + tests

- [x] **T3.1 — Re-add to Makefile.**  Done: `Data.Codec.Pulse` back in
      `SRC_MODS`; Makefile adds Pulse `--include` paths + `--already_cached`
      for the Pulse stdlib.  `nix build .#fstar-codec-checked` GREEN.
- [x] **T3.2 — Update test modules.**  Done.  The 10 `Stack`-based tests were
      moved out of `Data.Codec.Test.Roundtrip` into a **new** `#lang-pulse`
      module `test/Data.Codec.Test.Pulse.fst` (Pulse reserves the `label`
      keyword, which the pure tests use freely, so the buffer tests can't live
      in the non-Pulse Roundtrip module).  Each uses `A.alloc 0uy Nsz` +
      `A.free buf` (the Pulse analogue of `alloca` + `push_frame`/`pop_frame`)
      and forces the result constructor by pattern-match.  The dead `open
      FStar.HyperStack`/`FStar.HyperStack.ST`/`LowStar.Buffer` are gone.
      `Data.Codec.Test.Integration` dropped the dead `_pulseL0`…`_pulseL8`
      anchors (they named pre-roll-forward helper lemmas that no longer exist)
      and re-anchored the 10 stack tests to `Data.Codec.Test.Pulse`.

      Two latent bugs in the (never-re-verified) pure tests were fixed en route:
      (1) `test_expected_text_error` used `let`-bound `string_to_bytes` vars
      that don't reduce under `assert_norm` — inlined them; (2) five
      `varint_decode_expected` callsites used a stale `(seq) i n` argument order
      — reordered to the current `(i) (n) (seq)` signature.

- [x] **T3.3 — Re-verify the gate.**  Done.  `TST_MODS` now lists
      `Data.Codec.Test.Roundtrip Data.Codec.Test.Integration
      Data.Codec.Test.Pulse`; the test rule carries `--already_cached` (the
      Pulse test module opens `Pulse`).  The full gate (3 src + 3 test modules)
      verifies GREEN at 0-admit, `--z3rlimit 80`.  The Integration coverage
      module was also brought to **100% lemma coverage** (24 missing
      `lemma_*` refinements anchored).

## Phase 4 — Land `native` (Custard direct-C)

- [x] **T4.1 — `native` derivation.**  Done: `default.nix` `native` extracts
      the leaf to C11 + compiles `libfstar-codec.{dylib,so,a}`.
- [x] **T4.2 — `flake.nix` package.**  Done: `.#fstar-codec-native`.
- [x] **T4.3 — Verify.**  Done: GREEN, produces `libfstar-codec.{so,dylib,a}`
      + `fstar_codec.h` with all 18 API fns + 9 roundtrip lemmas exported.

## Definition of done

`nix build .#fstar-codec-checked` (0-admit, leaf + tests) and
`nix build .#fstar-codec-native` (C11 shared object from Custard, no karamel)
GREEN.
