# Change Proposal: codec-native-rust-wasm

## Summary

Make `fstar-codec` compile to C (`native`), `rust`, and `wasm` in addition to
the already-working `ocaml`, so the extracted library ships linkable artifacts
for every supported KaRaMeL/F* backend except F#.

## Motivation

`fstar-codec` currently verifies (0-admit) and extracts to `.krml` IR
(`checked`/`krml`), and compiles to OCaml (`ocaml`).  The three-layer build
landed in the `build-layer-separation` change.  But compiling `Data.Codec.Pulse`
(a real Low\* module, unlike the trivial template `Example.fst`) to C/Rust/Wasm
exposed a reachability defect: `Data.Codec.Pulse` `open`s `Data.Codec.Types`, which
drags the pure `list`-heavy combinator layer into the KaRaMeL closure, and the
rust/wasm backends cannot translate `FStar.List.Tot.Base.hd`/`.tail`.

## Scope

- **In scope**:
  - Narrow `open Data.Codec.Types` in `src/Data.Codec.Pulse.fst` to only the
    symbols it actually uses (`byte`, `byte_seq`, and the ghost-spec `byte_val`),
    removing the `FStar.List` reachability.
  - Land `native` (C shared object), `rust` (`.rlib`), `wasm` derivations with
    the known-good KaRaMeL flags (from the monorepo `tls/Makefile`).
  - Re-verify `Data.Codec.Pulse` at 0 admits.
- **Out of scope**:
  - F# (deliberately unsupported; no packaged runtime).
  - `exe` (the library has no `main`).
  - The `ocaml` target (already works; leave as-is).

## Risks

- Narrowing the `open` is F* source surgery on a 0-admit module; the
  re-verification (`nix build .#fstar-codec-checked`) is the gate, not the LSP
  (LSP is looser).

## Dependencies

- `build-layer-separation` (the three-layer build, already landed).
