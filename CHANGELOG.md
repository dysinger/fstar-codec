# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — initial extraction

### Added

- Extracted `Data.Codec` out of the original monorepo into a standalone
  repository built from `fstar-nix-flake-template`.
- Three source modules:
  - `Data.Codec.Types` — the `codec a` record and its 19+ base combinators.
  - `Data.Codec` — derived combinators, operator aliases, character predicates.
  - `Data.Codec.Low` — C-extractable `.Low` leaf codecs.
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
