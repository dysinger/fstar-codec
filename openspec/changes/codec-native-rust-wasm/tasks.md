# Implementation Tasks: codec-native-rust-wasm

**Change**: compile `fstar-codec` to `native`/`rust`/`wasm` (in addition to the
working `ocaml`).  Root cause is the `open Data.Codec.Types` in
`src/Data.Codec.Low.fst` leaking `FStar.List` reachability into the rust/wasm
backends.

## Phase 1 — Root-cause the source (the real fix)

- [x] **T1.1 — Inventory what `Data.Codec.Low` actually uses from
      `Data.Codec.Types`.**  Confirmed: `byte` (`U8.t`, Types:55); `byte_seq`
      (`Seq.seq byte`, Types:58); `byte_val` (Types:940, used ONLY in ghost
      `ensures`/lemma spec of `encode_bytes`/`decode_bytes`, never in extracted
      code).  Nothing else.  **CORRECTION (verified): the list reachability is
      NOT from `open Data.Codec.Types` — `open` spec symbols are erased.**  It
      is from two `<i>top-level spec helpers in `.Low` itself</i>:
      `varint_encode_pred` (a `prop` predicate) and `varint_decode_expected`
      (a `Pure decode_result_c` helper), both used only in `ensures`/lemmas but
      both extracted as `Prims_list`-reaching declarations.
- [x] **T1.2 — Prune the two spec helpers.**  `varint_encode_pred` → bare
      `noextract` keyword on its own line before `let` (the `[@ noextract]` /
      `[@@ noextract]` prefix attributes are a SYNTAX ERROR in F* 2025.10.x).
      `varint_decode_expected` → effect `Pure` → `Ghost` (prunes it from the
      `.krml`; `Pure` does not).  Both now vanish from `Data_Codec_Low.krml`
      (0 grep hits), removing `FStar.List` reachability.
- [x] **T1.3 — Re-verify 0 admits.**  `nix build .#fstar-codec-checked` GREEN,
      0 admits after the source change.

## Phase 2 — Land the three backends with known-good flags

- [x] **T2.1 — `native`.**  DONE.  `krml -skip-compilation -ccflavor clang` +
      `-warn-error -2 -9-16 -11 -26..28` + `-add-include
      '"krml/internal/compat.h"'` + minimal runtime `.krml` set (NOT the 3515
      glob) + link `libkrmllib.a`.  Produces `libfstar-codec.dylib`/`.so` +
      `Data_Codec_Low.h`.  nix GREEN.
- [ ] **T2.2 — `rust`.**  BLOCKED by a KaRaMeL Rust backend defect, NOT source.
      `PrintMiniRust.ml:172` maps `Constant.CInt` (`krml_checked_int_t`, from
      `U32.v`/`U8.v`/`%`/`/`) to an empty string → `let b4_val:  = …`.
      Additionally `-minimal -bundle` emits `crate::fstar`/`crate::prims`/
      `crate::lowstar::ignore` refs but KaRaMeL ships NO Rust runtime crate.
      Needs a KaRaMeL patch + runtime shims, or a rewrite of the encode/decode
      bodies to avoid mathematical ints.
- [ ] **T2.3 — `wasm`.**  BLOCKED by a KaRaMeL wasm backend limitation, NOT
      source.  `AstToCFlat.ml` `size_of` maps a wasm value to a SINGLE
      `I32`/`I64`; `decode_result_c` (20-byte flat struct / tagged union) is
      UNRETURNABLE from a wasm function (`size_of: this case should've been
      eliminated`).  `-fnostruct-passing` and `-by-ref` do NOT fix it — no
      multi-value struct returns.  Needs an API refactor to out-parameter
      returns.
- [x] **T2.4 — Do NOT glob all 3515 `${fstar-krml}/krml/*.krml`.**  DONE.
      `default.nix` now passes a `krml-runtime` list of the ~15 modules the
      generated C actually references (discoverable via `grep -oE
      'FStar_[A-Za-z0-9_]+' *.c | sort -u`).  The broken space-joined
      `-drop Data_Codec_Types Data_Codec …` (→ "Unknown file extension for
      Data_Codec") is REMOVED — `-drop` takes ONE comma-separated name, and it
      is unneeded now that the `.krml` is clean.

## Phase 3 — Verify + commit

- [x] **T3.1 — Verify the achievable targets.**  `nix build
      .#fstar-codec-checked .#fstar-codec-krml .#fstar-codec-native
      .#fstar-codec-ocaml` GREEN (rust/wasm blocked per T2.2/T2.3).
- [x] **T3.2 — Exercise outputs.**  `native` produces `libfstar-codec.dylib`
      (37168 bytes) + `Data_Codec_Low.h`.
- [ ] **T3.3 — Update README** target table to list the six targets AND mark
      `rust`/`wasm` as blocked by KaRaMeL backend limitations.
- [ ] **T3.4 — Commit** (NOT `AGENTS.md`).

## Definition of done

`native`/`ocaml`/`checked`/`krml` GREEN; `rust`/`wasm` are BLOCKED by verified
KaRaMeL backend defects (not source); `Data.Codec.Low` remains 0-admit.
