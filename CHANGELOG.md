# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed

- **Deleted five dead `opt_prefixed_*_eq` accessor lemmas** from
  `Data.Codec.Types` (`lemma_opt_prefixed_{dec,enc,rest_cond,wfcv,wfcv_prop}_eq`).
  Each was referenced **exactly once in the tree — its own definition** — and
  zero times in `test/`, so nothing could break and nothing was anchored.  The
  `opt_prefixed` combinator and its six helper functions are untouched.

### Fixed

- **`README.md` no longer states the `codec_v2` end state in the present
  tense.**  Every `[S*]` now carries a `(shipped)` / `(codec_v2 target)` marker;
  `[S2]` (structural consumed-byte bound) is re-scoped to a target, since
  `dec_consumed_bound` is still a field that 22 of 26 literals fill with
  `(fun s -> ())` and no combinator instantiates `codec_v2`.  `[W5]` is scoped
  likewise (`map_retract_on_image` is not in `src/`; `src/`'s `map_` has no
  `law_bwd`).  Adds **`[W10]`**: `varint.wfcv` reaches `2^35` but the Pulse/C
  path is `U32.t`, so `[2^32, 2^35)` has a spec and no runtime path — previously
  cited as headroom, now stated as a gap.
- **The lemma count is honest and generated.**  It was `67`, which undercounted
  by 9 because Pulse's roundtrip lemmas are `fn lemma_*`, not `let`.  It is now
  **71** (62 `let` + 9 `fn`) *after* the five deletions above, stated together
  with the command that produces it.  `[S6]` and the Representations table were
  corrected in all three places the number appeared.
- **Every `let` lemma now has a coverage anchor.**  `no_overlap_cons`,
  `scan_prefix`, `scan_cons_no_prefix` and `split_head` were used by `src/` (or,
  for `split_head`, by future `codec_v2` `law_bwd`s) but not referenced by
  `Data.Codec.Test.Integration`, so deleting them left the build green.
  Deletion-tested: removing each now fails the build.  `opt_prefixed`, its
  helpers, and `remainder` are anchored too.  `[W7]` rewritten to record the
  closed hole (it had claimed "exactly one combinator lacks an anchor").
- **`codec_v2`'s doc comment refreshed** — it still said `word16*`/`word32*`
  were "NOT yet proved" (proved 2026-11-07) and cited "15 modules + 2 asserted
  refutations" (now 28 + 3, and the count is cited from `spike-run.sh` rather
  than carried).

### Added

- `check-readme-parity.sh` — asserts the eight `##` sections match
  `../lean-codec/README.md` in name and order, that all 33 anchors
  (`[D1]`–`[D13]`, `[S1]`–`[S9]`, `[W1]`–`[W10]`, `[O1]`) are defined exactly
  once, and that three blocks a past restructure silently deleted are present.
  Mutation-tested: renaming a heading, renumbering an anchor, or dropping a
  block each fail it.

### Changed

- Split `Data.Codec.Types` into a format-agnostic core plus a new
  `Data.Codec.Text` module holding the ASCII text leaves (`text`,
  `string_to_bytes`, `string_is_ascii`), the byte predicates (`is_upper` …
  `is_printable`, `char_to_byte`), the `char_is_*` family, and `digit_byte`.
  The public surface is unchanged: `Data.Codec` re-exports all three modules,
  and all seven downstream consumers rebuild with **zero source changes**.
  `Types` 4133 → 4082 lines; `Data.Codec` 244 → 140.  Behaviour is identical
  (`text` remains ASCII-only; AUDIT §2a is untouched).  A `Data.Codec.Binary`
  split was evaluated and deferred — the Pulse `codec_t` dispatcher depends on
  the integer leaves, so they cannot move until that dispatcher is split.

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
  - `Data.Codec.Test.Roundtrip` — 118 pure roundtrip/error-path tests.
  - `Data.Codec.Test.Pulse` — 10 buffer-based Pulse roundtrip/error tests.
  - `Data.Codec.Test.Integration` — binds every lemma/test, enforcing coverage.
- Nix flake targets: `.#checked`, `.#ocaml`, `.#native`, `.#fsharp`.
- Dual licensing: AGPL-3.0-or-later, or a commercial license from the author.

### Notes

- Zero admits / zero magic / zero `assume` across all modules.
- The authoritative verification gate is `.#checked`; the Pulse leaf extracts
  to C11/OCaml/F# via Custard (`--custard_backend C`).
