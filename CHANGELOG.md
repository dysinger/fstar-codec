# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Renamed the C leaf `Data.Codec.Low` → `Data.Codec.Pulse` (the KaRaMeL `.Low`
  convention is retired; the Pulse/Custard layer is the successor).  This
  pins the convention for future standalone xeno extractions: each `.Low`
  module becomes `.Pulse` as it is ported to F\* v2026.09.20.
- Ported `Data.Codec.Pulse` from KaRaMeL Low\* (`Stack` + `LowStar.Buffer`) to
  Pulse (`fn` + `Pulse.Lib.Array`), 0-admit, extracting to C11 via Custard.

### Changed

- Rolled F\* forward to `v2026.09.20+lsp` (first stable tag shipping the
  Custard extractor).
- Removed the KaRaMeL/Low\* toolchain and all its targets (`krml`, `native`,
  `rust`, `wasm`) — F\* `v2026.09.20` deleted the `FStar.HyperStack` /
  `LowStar.Buffer` stdlib, so the `.Low` leaf cannot typecheck anymore.
- `checked` now verifies the pure spec (`Data.Codec.Types` + `Data.Codec`);
  `ocaml` packages only the pure spec.  `Data.Codec.Pulse` + its two test
  modules are out of the build pending a Pulse port.

### Source drift fixes

- Removed `open FStar.Mul` and `Prims.op_Multiply` (both deleted upstream).
- Removed `--split_queries always` from `#push-options` (option deleted).

## [0.1.0] — initial extraction

### Added

- Extracted `Data.Codec` out of the original monorepo into a standalone
  repository built from `fstar-nix-flake-template`.
- Three source modules:
  - `Data.Codec.Types` — the `codec a` record and its 19+ base combinators.
  - `Data.Codec` — derived combinators, operator aliases, character predicates.
  - `Data.Codec.Pulse` — C-extractable `.Low` leaf codecs.
- Two test modules:
  - `Data.Codec.Test.Roundtrip`
  - `Data.Codec.Test.Integration`
- Nix flake targets: `.#fstar-codec-checked` (verify) and
  `.#fstar-codec-krml` (KaRaMeL extraction of the `.Low` module).
- Dual licensing: AGPL-3.0-or-later, or a commercial license from the author.

### Notes

- Zero admits / zero magic / zero `assume` across all modules.
- The shipped surface is the verified `.checked` cache plus the `.krml`
  intermediate IR; C co-extraction of the `.Low` layer is a separate
  KaRaMeL/krmllib concern (see the `flake.nix` note about
  `FStar.UInt8.uint_to_t`).
