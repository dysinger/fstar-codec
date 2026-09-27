# Implementation Tasks: low-pulse-port

**Change**: rewrite `Data.Codec.Low` from KaRaMeL Low\* (`Stack` +
`LowStar.Buffer`) to Pulse (`fn` + `Pulse.Lib.*`) so it extracts to C via
Custard (`--custard_backend C`), restoring the `native` target.

> **Prerequisite**: the `fstar-roll-forward` change is landed (F\*
> `v2026.09.20+lsp` + Custard + karamel removed).

## Phase 1 — Spike the Pulse idiom (de-risk before the full port)

- [ ] **T1.1 — Minimal Pulse leaf.**  Create a throwaway module (not wired
      into the build) that ports the *simplest* leaf — `encode_token` /
      `decode_token` — to Pulse: `fn encode_token (v: U32.t) (b: vec U8.t)
      (i: U32.t)` with a separation-logic pre/post replacing the `Stack`
      `requires`/`ensures`+`modifies`.
- [ ] **T1.2 — Extract it via Custard.**  Run
      `fstar.exe --codegen Custard --custard_backend C
      --custard_monomorphize_types true --custard_entry_module <m>` and confirm
      C11 output compiles with `cc` and no karamel headers.
- [ ] **T1.3 — Pin the idiom.**  Record the exact `open` set, the buffer
      primitive (Vec vs Array), and the separation-logic shorthand that
      compiles + verifies, in `AGENTS.md` so the remaining 7 leaves copy it.

## Phase 2 — Full leaf port

- [ ] **T2.1 — Types.**  Carry over `codec_t`, `error_code_c`,
      `decode_error_c`, `decode_result_ok`, `decode_result_c` unchanged (they
      are plain F\* data types, no `Stack`/`LowStar.Buffer`).
- [ ] **T2.2 — Encoders.**  Port `encode_token`, `encode_byteval`,
      `encode_uint8`, `encode_word16be/le`, `encode_word32be/le`,
      `encode_varint` (8 total) to Pulse `fn`.
- [ ] **T2.3 — Decoders.**  Port `decode_token`, `decode_byteval`,
      `decode_uint8`, `decode_word16be/le`, `decode_word32be/le`,
      `decode_varint` (8 total) to Pulse `fn`, returning `decode_result_c`.
- [ ] **T2.4 — Dispatch.**  Port `encode_bytes` / `decode_bytes` (the
      `match c with ...` dispatchers) to Pulse.
- [ ] **T2.5 — Ghost spec + constants.**  Re-express `varint_encode_pred`,
      `varint_decode_expected`, and the arithmetic lemmas as ghost/Pure code
      (they are already `noextract`/`Ghost`; only the buffer-reading bodies
      change to Pulse's view of the buffer).
- [ ] **T2.6 — Roundtrip lemmas.**  Port the `lemma_low_roundtrip_*` and
      `lemma_low_encode_decode_match` proofs to Pulse's separation-logic
      framing (the hard part — these currently thread `h_mid` heaps via
      `FStar.HyperStack.ST.get ()`).

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
