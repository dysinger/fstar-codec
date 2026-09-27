# Implementation Tasks: low-pulse-port

**Change**: rewrite `Data.Codec.Low` from KaRaMeL Low\* (`Stack` +
`LowStar.Buffer`) to Pulse (`fn` + `Pulse.Lib.*`) so it extracts to C via
Custard (`--custard_backend C`), restoring the `native` target.

> **Prerequisite**: the `fstar-roll-forward` change is landed (F\*
> `v2026.09.20+lsp` + Custard + karamel removed).

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

- [ ] **T3.1 — Re-add to Makefile.**  Restore `Data.Codec.Low` to `SRC_MODS`
      and the two test modules to `TST_MODS`.
- [ ] **T3.2 — Update test modules.**  Rewrite
      `test/Data.Codec.Test.{Roundtrip,Integration}.fst`'s `Data.Codec.Low`
      references to the Pulse API surface.
- [ ] **T3.3 — Re-verify the gate.**  `nix build .#fstar-codec-checked`
      GREEN at 0-admit with the leaf + tests back in.

## Phase 4 — Land `native` (Custard direct-C)

- [ ] **T4.1 — `native` derivation.**  Add a `native` target in `default.nix`
      that runs `fstar.exe --codegen Custard --custard_backend C
      --custard_monomorphize_types true --custard_entry_module Data.Codec.Low`
      and compiles the emitted `.c` to a shared object with `cc` (no karamel).
- [ ] **T4.2 — `flake.nix` package.**  Expose `.#fstar-codec-native`.
- [ ] **T4.3 — Verify.**  `nix build .#fstar-codec-native` GREEN, producing
      `libfstar-codec.{so,dylib}` + a `Data_Codec_Low`-shaped header.

## Definition of done

`nix build .#fstar-codec-checked` (0-admit, leaf + tests) and
`nix build .#fstar-codec-native` (C11 shared object from Custard, no karamel)
GREEN.
