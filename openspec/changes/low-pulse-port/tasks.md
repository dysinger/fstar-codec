# Implementation Tasks: low-pulse-port

**Change**: rewrite `Data.Codec.Low` from KaRaMeL Low\* (`Stack` +
`LowStar.Buffer`) to Pulse (`fn` + `Pulse.Lib.*`) so it extracts to C via
Custard (`--custard_backend C`), restoring the `native` target.

> **Prerequisite**: the `fstar-roll-forward` change is landed (F\*
> `v2026.09.20+lsp` + Custard + karamel removed).

## ⚠️ BLOCKED — `Data.Codec.Low` verify HANGS (non-terminating SMT query)

T3/T4 are **blocked**: `Data.Codec.Types` and `Data.Codec` verify, then the
`Data.Codec.Low` `fstar.exe` run hangs forever (35+ min at 0% CPU, `status =
stopped`).  It verified + extracted green **earlier this session** (commit
`a34c984` produced `libfstar-codec.dylib`), so this is a flaky/non-terminating
SMT query — not a type error.  Prime suspects (the `--z3rlimit`-sensitive
word32 roundtrip/encode `fn`s) and a step-by-step isolation plan
(`--log_queries` + `timeout`, raise rlimit per-`fn` via `#push-options`, lift
byte-extraction into a `Lemma`, or use a `noextract` helper predicate) are in
[`AGENTS.md`](../../../AGENTS.md) § "BLOCKED".

**T3.2 (test rewrite) depends on this** — the test modules `open Data.Codec.Low`.

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
- [x] **T2.6 — Roundtrip lemmas.**  Done: `lemma_low_roundtrip_{token,
      byteval,uint8,word16be,word16le,word32be,word32le,varint}` + `lemma_low_
      encode_decode_match` ported to Pulse `fn` and verified.  Much easier than
      feared: the pure `codec` `.enc`/`.dec` are record projections that
      compute, so `dec (enc x)` reduces and SMT discharges the roundtrip
      without the old `lemma_word32_shift_bytes` / `h_mid` heap threading.

## Phase 3 — Restore the build + tests

- [x] **T3.1 — Re-add to Makefile.**  Done: `Data.Codec.Low` back in
      `SRC_MODS`; Makefile adds Pulse `--include` paths + `--already_cached`
      for the Pulse stdlib.  `nix build .#fstar-codec-checked` GREEN.
- [ ] **T3.2 — Update test modules.**  Rewrite the two test modules' Low*/
      `Stack` references to the Pulse surface.

      **`test/Data.Codec.Test.Roundtrip.fst`** (867 lines, 120 tests): the
      **pure** tests (everything except the 10 `Stack`-based ones) reference
      `Data.Codec`/`Data.Codec.Types` and are already Pulse-compatible.  The
      work is the **10 `Stack`-based roundtrip tests** at ~line 461–577
      (`test_stack_{token,uint8,byteval,word16be,word32be,word16le,word32le,
      varint}_roundtrip`, `test_stack_varint_overflow`,
      `test_stack_varint_dispatch_roundtrip`).  They currently use
      `alloca 0uy Nul` + `LB.upd`/`LB.index` + the `Stack` effect + `opens`
      `FStar.HyperStack`/`FStar.HyperStack.ST`/`LowStar.Buffer` (all deleted).
      Rewrite to Pulse `fn` using `A.alloc`/`A.with_local` + `b.(j) <- x` +
      the `#lang-pulse`/`open Pulse`/`module A = Pulse.Lib.Array` idiom from
      `src/Data.Codec.Low.fst` (and `spike/Data.Codec.Spike.fst`).

      **`test/Data.Codec.Test.Integration.fst`** (391 lines): a coverage-anchor
      module that `open Data.Codec.Low` and names ~20 leaf definitions to force
      verification.  Its `_lowL0`…`_lowL8` anchors reference **dropped helper
      lemmas** (`lemma_pow2_32`, `lemma_buffer_length_bound`,
      `lemma_decode_guard_implies_len_pos`, `lemma_lte_add2/4_implies_len_ge_2/4`,
      `lemma_u32_add_no_overflow`, `lemma_byteval_index_from_slice`,
      `lemma_word32_shift_bytes`, `lemma_encode_varint_matches_pure`,
      `lemma_encode_varint_eq_buffer`, `lemma_decode_varint_roundtrip`) that the
      Pulse port **no longer needs** (proofs are automatic now — see T2.6).
      Options: drop those anchors, or keep them by re-exporting the (now trivial)
      corresponding proofs.  The `_low0`…`_low22b` function/lemma anchors map
      cleanly to the Pulse `fn`s (encode/decode/encode_bytes/decode_bytes/
      `lemma_low_roundtrip_*`/`lemma_low_encode_decode_match`).

      Both files also `open FStar.HyperStack`/`FStar.HyperStack.ST`/
      `LowStar.Buffer` — remove those opens.

- [ ] **T3.3 — Re-verify the gate.**  Add the two test modules to `TST_MODS`
      in the Makefile (`TST_MODS := Data.Codec.Test.Roundtrip
      Data.Codec.Test.Integration`), then `nix build .#fstar-codec-checked`
      GREEN at 0-admit with tests restored.  (The leaf alone is already green;
      this closes the loop.)

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
