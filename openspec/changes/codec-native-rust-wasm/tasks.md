# Implementation Tasks: codec-native-rust-wasm

**STATUS: SUPERSEDED by F\* v2026.09.20.**  This change targeted the old
KaRaMeL `native`/`rust`/`wasm` toolchain, which v2026.09.20 **removed
entirely**.  `native` is now GREEN via Custard's `--custard_backend C`; `rust`
and `wasm` are permanently dropped (no karamel, no wasm backend).  The only
remaining open boxes below (T2.2 rust / T2.3 wasm / T3.3 + T3.4 bookkeeping)
are moot and archived here for the record.

**Change**: compile `fstar-codec` to `native`/`rust`/`wasm` (in addition to the
working `ocaml`).  Root cause is the `open Data.Codec.Types` in
`src/Data.Codec.Pulse.fst` leaking `FStar.List` reachability into the rust/wasm
backends.

## Phase 1 — Root-cause the source (the real fix)

- [x] **T1.1 — Inventory what `Data.Codec.Pulse` actually uses from
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
      `.krml`; `Pure` does not).  Both now vanish from `Data_Codec_Pulse.krml`
      (0 grep hits), removing `FStar.List` reachability.
- [x] **T1.3 — Re-verify 0 admits.**  `nix build .#fstar-codec-checked` GREEN,
      0 admits after the source change.

## Phase 2 — Land the three backends with known-good flags

- [x] **T2.1 — `native`.**  DONE.  `krml -skip-compilation -ccflavor clang` +
      `-warn-error -2 -9-16 -11 -26..28` + `-add-include
      '"krml/internal/compat.h"'` + minimal runtime `.krml` set (NOT the 3515
      glob) + link `libkrmllib.a`.  Produces `libfstar-codec.dylib`/`.so` +
      `Data_Codec_Pulse.h`.  nix GREEN.
- [x] **T2.2 — `rust`.**  ~~BLOCKED by a KaRaMeL Rust backend defect, NOT source.~~
      **Superseded — KaRaMeL deleted upstream in v2026.09.20; the `rust`
      backend no longer exists.**  (`PrintMiniRust.ml:172` maps
      `Constant.CInt` to an empty string → `let b4_val:  = …`, and KaRaMeL ships
      no Rust runtime crate — but the fix is moot: `rust` is dropped with the
      whole KaRaMeL layer, not patched.)
- [x] **T2.3 — `wasm`.**  ~~BLOCKED by a KaRaMeL wasm backend limitation, NOT
      source.~~  **Superseded — the wasm backend was deleted upstream in
      v2026.09.20; no wasm target exists.**  (`AstToCFlat.ml` `size_of` mapped a
      wasm value to a single `I32`/`I64`, making `decode_result_c` unreturnable
      — moot now.)
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
      (37168 bytes) + `Data_Codec_Pulse.h`.
- [x] **T3.3 — Update README** target table.  **Superseded.**  The six-target
      matrix is obsolete: README/AGENTS now document the four live targets
      (`checked`/`ocaml`/`native`/`fsharp`) and record `rust`/`wasm`/`krml` as
      removed-with-KaRaMeL (see fstar-roll-forward + AGENTS.md backend matrix).
- [x] **T3.4 — Commit.**  Superseded — folded into the fstar-roll-forward and
      pulse-fsdoc-finalize commits (the rust/wasm verdict is recorded there,
      not as a standalone `codec-native-rust-wasm` commit).

## Definition of done

`native`/`ocaml`/`checked`/`krml` GREEN; `rust`/`wasm` are BLOCKED by verified
KaRaMeL backend defects (not source); `Data.Codec.Pulse` remains 0-admit.
