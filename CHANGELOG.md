# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `satisfy_many0` / `satisfy_many1` — variable-width predicate-run combinators
  in `Data.Codec.Types` (combinators 21/22), each `(byte -> Tot bool) ->
  codec (list byte)`.  A generic (symbolic-`f`) roundtrip plus
  `dec_err_bound`/`dec_consumed_bound`, proved 0-admit at `--z3rlimit ≤ 120`;
  the run scan is a top-level `let rec` at the list level with the
  `lemma_seq_to_list_of_list_append` §11 bridge.  Facade long-name aliases
  `many0`/`many1` in `Data.Codec`.

### Changed

- Renamed the C leaf `Data.Codec.Low` → `Data.Codec.Pulse` (the KaRaMeL `.Low`
  convention is retired; the Pulse/Custard layer is the successor).  This
  pins the convention for future standalone xeno extractions: each `.Low`
  module becomes `.Pulse` as it is ported to F\* v2026.09.20.
- Ported `Data.Codec.Pulse` from KaRaMeL Low\* (`Stack` + `LowStar.Buffer`) to
  Pulse (`fn` + `Pulse.Lib.Array`), 0-admit, extracting to C11 via Custard.
- Rolled F\* forward to `v2026.09.20+lsp` (first stable tag shipping the
  Custard extractor).
- Removed the KaRaMeL/Low\* toolchain and all its targets (`krml`, `native`,
  `rust`, `wasm`) — F\* `v2026.09.20` deleted the `FStar.HyperStack` /
  `LowStar.Buffer` stdlib, so the `.Low` leaf cannot typecheck anymore.
- `checked` now verifies the pure spec (`Data.Codec.Types` + `Data.Codec` +
  `Data.Codec.Pulse`) plus the three test modules; `ocaml` packages the pure
  spec + Pulse leaf.

### Source drift fixes

- Removed `open FStar.Mul` and `Prims.op_Multiply` (both deleted upstream).
- Removed `--split_queries always` from `#push-options` (option deleted).

## [0.1.0] — initial extraction

### Added

- Extracted `Data.Codec` out of the original monorepo into a standalone
  repository built from `fstar-nix-flake-template`.
- Three source modules:
  - `Data.Codec.Types` — the `codec a` record and its 22 base combinators
    (13 primitives + 7 combinators + 2 variable-width predicate runs;
    `one_of`/`take_until` are (enc, dec, wfcv) triple helpers, not records).
  - `Data.Codec` — derived combinators, operator aliases, character predicates.
  - `Data.Codec.Pulse` — C-extractable Pulse leaf codecs (8 types), buffer
    I/O, and roundtrip lemmas.
- Three test modules:
  - `Data.Codec.Test.Roundtrip` — 115 pure roundtrip/error-path tests.
  - `Data.Codec.Test.Pulse` — 10 buffer-based Pulse roundtrip/error tests.
  - `Data.Codec.Test.Integration` — binds every lemma/test, enforcing coverage.
- Nix flake targets: `.#checked`, `.#ocaml`, `.#native`, `.#fsharp`.
- Dual licensing: AGPL-3.0-or-later, or a commercial license from the author.

### Notes

- Zero admits / zero magic / zero `assume` across all modules.
- The authoritative verification gate is `.#checked`; the Pulse leaf extracts
  to C11/OCaml/F# via Custard (`--custard_backend C`).
