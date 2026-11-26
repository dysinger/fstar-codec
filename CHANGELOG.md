# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **`codec_v2`'s laws are now UNCONDITIONAL — the paper's `Iso` (F94).**
  `law_fwd` is `requires enc x = Some e` and nothing else; `wfcv` and
  `rest_cond_v` are no longer law hypotheses (they remain fields for the C
  tier).  This matches `PAPER.md` §3.1, whose `Iso` law carries no side
  condition; `wfcv`/`rest_cond` are extraction artefacts (README `[D9]`,
  `[W1]`).  The five shipped instances were migrated.  Two needed their value
  guard moved **into `enc`** (the domain is now exactly `enc`'s image):
  `satisfy_v.enc v = if f v then Some (create 1 v) else None`, and
  `pure_v.enc v = if v = x then Some [] else None` (the old constant form made
  the law false).  `make check` green (11 modules), 0 admits.

### Added

- **The six structural facets on `codec_v2` (T4.2b).**  `take_v`, `then_drop_v`,
  `drop_then_v`, `between_v`, `optional_v` and `choice_v`, in
  `Data.Codec.Types` with both laws, transcribed from 0-admit spikes
  (`spike-f98-facets.fst`, `spike-f98-optional.fst`,
  `spike-f100-choice-shape.fst`).  F95 expected all six to be "one
  `map_v`-with-`iso` step"; F98 measured that this holds for exactly **one**
  (`optional`, whose `either a unit ≅ option a` collapse is a bijection).
  `take_v` is a definition over `count_v`/`token_v`; `then_drop_v` and
  `drop_then_v` are lenses over `product_v`'s components; `between_v` is two of
  those composed.  **`choice_v` takes `squash (disjoint_all_v c1 c2)` as a
  parameter**, so no law carries a side condition — F98's `choice_ok` was
  disjunctive and therefore satisfied when both arms encode, which is the one
  case `choice` cannot resolve.  Replacing the parameter with `squash True`
  fails verification, so the witness is load-bearing.  `make check` green
  (11 modules), 0 admits; spike suite exit 0, 14 refutations.

- **Structural combinators on `codec_v2` (T4.2).**  `product_v`, `sum_v`,
  `map_v` (the paper's IsoFunctor `$`, taking an `iso a b` — no retract side
  condition, closing `[W5]`), `count_v`, and `label_v`, all in
  `Data.Codec.Types` with both laws.  Transcribed from 0-admit spikes on the
  shipped record (`spike-f94-paper-iso.fst`, `spike-sum.fst`,
  `spike-f95-t42.fst`).  `count_v` carries its "exactly m elements" guard in
  `enc`'s image, as F94's rule requires.  `make check` green (11 modules),
  0 admits; the two deleted-hypothesis deletion tests are gated in the change's
  spike suite.

- **`codec_v2` instances begin to land in `src/` (T4.0b, T4.1).**  The strict
  type had no inhabitant in the shipping build, so a defect in the *type* would
  have surfaced 27 times during the M3 migration instead of once.  Five leaves
  are now strict: `token_v`, `byte_val_v`, `satisfy_v`, `pure_v`
  (`Data.Codec.Types`) and `text_v` (`Data.Codec.Text`).  Both laws on each,
  transcribed from the proofs in `codec-strict-isomorphism`'s spike suite;
  `make check` green (11 modules), 0 admits.  `text_v` needed one extra lemma
  (`lemma_text_v_ok`): SMT will not reduce a conditional decoder's `if` chain
  through its definition, so the successful branch is stated as a hypothesis
  and the solver inverts the decoder instead of unfolding it.

- **`bench/` — the C benchmark harness (`REQ-ISO-C-PERF`, T9.1/T9.2).**  There
  was no benchmark in this repository, so the "fast in C" conjunct of the
  delivery criterion was unmeasured.  `bench/bench-pulse.c` drives the extracted
  C through `codec.h`; `bench/bench-ref.c` is a hand-written C baseline for the
  same 8 wire formats on the same fixed 16-byte, 7-field message;
  `bench/run.sh` extracts the C **before** and **after** the canonicalisation
  guard and reports both.  New nix target `.#bench` builds and runs it, so the
  recorded figures are a build artifact.  Measured (aarch64-darwin, `cc -O2`):
  decode at parity with hand-written C (`decode/message` 1.00x,
  `decode/leaves` 0.99x), encode 1.49x–1.63x, `roundtrip/message` 1.22x; the
  group-zero guard costs **+12%** on a 2-byte varint decode (~0.25 ns).

### Fixed

- **`README.md` `[S6]`: the lemma count was stale and the anchoring claim was
  false for `codec_v2`.**  The count is now 142 (`100 let + 33 let rec + 9 fn`),
  recomputed rather than incremented.  "Every lemma anchored against deletion"
  was true for the legacy `codec` tier and false for the whole `codec_v2` tier
  (F94–F102's witnesses are `0` references in the anchor module); `[S6]` now
  says so and names the gap instead of implying coverage it does not have.

- **`README.md` `[W1]`, `[D2]` and `[O1]`: three wrong reasons, same decisions
  (T3.6/T3.7, `codec-strict-isomorphism` F89).**  `[W1]`'s ledger row said an
  unconditional law was "not achievable while the C path stays single-answer"
  and named `[O1]` as the route.  `rest_cond` is an artefact of **prefix**
  decoding, not of the single-answer decoder: under `[O1]` the maximal answer
  for a prefix read of `enc xs ++ r` is still `(xs, |xs|)`, so `rest_cond_v`
  survives.  `[D2]` justified itself with "a returned list cannot lower to a
  buffer and cursor", which is false for a list of suffixes; the real
  constraint is the C ABI returning one `decode_result_c` by value.  Every
  *decision* in those entries stands — only their stated causes were wrong, and
  the corrected causes change what `[O1]` would buy.
- **The `native`, `ocaml`, and `fsharp` derivations used a flag this toolchain
  rejects.**  All three passed `--codegen Custard` (and `--custard_backend`),
  while the accepted enum is `OCaml|FSharp|KrmlC|KrmlRust|C|Cherry|Plugin` and
  `--custard_backend` does not exist — so `nix build .#native` could never have
  produced the C.  The flag is now `--codegen C`, rooted with
  `--custard_entry_module Data.Codec.Pulse --custard_c_no_prefix
  Data.Codec.Pulse`.  Measured end to end: verify 4 modules from cold + extract +
  compile `-Werror` = 63 s.  The "`.#native` hangs at 0% CPU" note was the
  rejected flag, and a cold `Types` verify is 24 s and green — not a hang.
- **`.#ocaml` needs `-o` to name each `.ml`.**  Custard's OCaml backend writes
  `Custard.ml` regardless of module, so three invocations overwrote one another
  and `dune`'s `modules` list could not be satisfied.  Each pure module now
  emits `$(module with dots → underscores).ml`; `--codegen OCaml` also needs an
  entry point on this toolchain (`--custard_entry_module`).
- **`README.md` states the measurement instead of calling it unmeasured.**  The
  Performance section's "no benchmark exists / no throughput claim" table is
  replaced by the measured figures and the two gaps that genuinely remain
  (`[W6]` C reach, `[W10]` C domain).  `[W8]` is marked closed (F84/F85 + the
  benchmark), and the `varint` row of the law table is updated.

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
- **The lemma count is honest and generated.**  It was `67`, which matched only
  `let lemma_*` — F\* has **three** declaration forms, and the pattern missed
  `let rec lemma_*` (31) and Pulse's `fn lemma_*` (9).  The total is **102**
  (62 `let` + 31 `let rec` + 9 `fn`; `Types` alone has 88), published with the
  per-form split and the one command that produces it.  Two earlier figures,
  `76` and `71`, were published as verified and were each wrong.  `[S6]` and the
  Representations table corrected in all three places the number appeared.
- **Every lemma now has a coverage anchor.**  Eight lemmas were unanchored in
  `src/`, in three classes: four used by `src/` (`no_overlap_cons`,
  `scan_prefix`, `scan_cons_no_prefix`, `split_head`), and four `let rec`
  lemmas (`lemma_is_prefix_of_self_append`,
  `lemma_is_prefix_of_app_ignores_tail`, `lemma_scan_until_split_general`,
  `lemma_sep_by1_enc_nonempty`) that the original `^let lemma_` sweep could not
  see at all.  All anchored and deletion-tested: removing any of them now fails
  the build.  `opt_prefixed`, its helpers, and `remainder` are anchored too.
  `[W7]` rewritten to record the closed hole — including that the repair itself
  failed once, because the sweep and the count shared the same blind spot.
- **`codec_v2`'s doc comment refreshed** — it still said `word16*`/`word32*`
  were "NOT yet proved" (proved 2026-11-07) and cited "15 modules + 2 asserted
  refutations" (now 28 + 3, and the count is cited from `spike-run.sh` rather
  than carried).

### Added

- `check-readme-parity.sh` — asserts the eight `##` sections match
  `../lean-codec/README.md` in name and order, that the published lemma counts
  match the three-form enumeration (`62 let + 31 let rec + 9 fn = 102`), that
  all 33 anchors (`[D1]`–`[D13]`, `[S1]`–`[S9]`, `[W1]`–`[W10]`, `[O1]`) are defined exactly
  once, and that three blocks a past restructure silently deleted are present.
  Mutation-tested: renaming a heading, renumbering an anchor, dropping a block,
  restating a stale total, or corrupting/removing a per-form row each fail it.

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
