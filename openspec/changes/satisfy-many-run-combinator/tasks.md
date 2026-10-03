# Implementation Tasks: satisfy-many-run-combinator

> **Multi-session scope**: this change is **Session A** of the variable-width
> codec plan documented in [`ROADMAP.md`](ROADMAP.md) (Session B = `fstar-mime`
> rewire, Session C = `fstar-protobuf`).  Read the roadmap first; it is the
> canonical cross-session source of truth.

**Change**: add a variable-width predicate-run combinator (`satisfy_many0` /
`satisfy_many1`) to `Data.Codec`, with a generic roundtrip, so downstream
packages (mime first) build their codecs from combinators instead of bespoke
scanners (Mandate 22).

> **Reference**: the run roundtrip is already proven concretely in-tree by
> `lemma_digits_process_list` (a variable-length `is_digit` run, list induction,
> framing `Seq.length r = 0 ∨ not (is_digit (Seq.index r 0))`).  This change
> generalizes that from `is_digit` to a symbolic `f : byte -> bool`, placing the
> proof in `Data.Codec.Types` where the `Seq.seq_to_list` bridge is transparent.

## Phase 1 — Spike the symbolic-`f` run (de-risk)

- [x] **T1.1 — List-level run scan.**  Add `satisfy_run_scan (f: byte -> Tot bool)
      (bs: list byte) : Tot (list byte & list byte)` as a **top-level** `let rec`
      (NOT a nested `let rec read` — Warning 242).  Mirror `scan_until_split`.
- [x] **T1.2 — Generic self-scan lemma.**  Prove `lemma_satisfy_run_scan_self`
      (`satisfy_run_scan f (xs ++ rest) == (xs, rest)` when `for_all f xs` and
      `rest` is empty-or-head-rejected) by list induction.  The `fstar-mime`
      spike already verified this shape; port it.
- [x] **T1.3 — Symbolic roundtrip.**  Prove `dec (seq_of_list xs ++ r) ==
      Inr (xs, length xs)` by chaining `lemma_seq_to_list_of_list_append`
      (already in-module) + `lemma_satisfy_run_scan_self`.  Confirm it discharges
      at `--z3rlimit ≤ 120` for a symbolic `f` (the §11 wall is crossed *here*,
      inside the defining module, not at the consumer).

## Phase 2 — `satisfy_many0` / `satisfy_many1` combinators

- [x] **T2.1 — `satisfy_many0`.**  `codec (list byte)` with `enc = seq_of_list`,
      `dec` over `satisfy_run_scan`, `wfcv = for_all f`, framing `rest_cond`,
      `roundtrip`/`dec_err_bound`/`dec_consumed_bound` from Phase 1.
- [x] **T2.2 — `satisfy_many1`.**  Either `map_`-guarded non-empty over
      `satisfy_many0`, or a direct sibling — pick whichever proves ≤ rlimit 120
      with a clean generic roundtrip.
- [x] **T2.3 — Numbering + fsdoc.**  Add the combinator to the module header's
      combinator list and give it a fsdoc consistent with the existing 1-22.
- [x] **T2.4 — Bound lemmas.**  Prove `dec_err_bound`/`dec_consumed_bound`
      (trivial: `length run ≤ length s`; mirror `take_until`'s).

## Phase 3 — Facade long names + operators

- [x] **T3.1 — Long-name aliases.**  In `Data.Codec`: `many (f) = satisfy_many0 f`,
      `many1 (f) = satisfy_many1 f` (or `some`/`some1`), following `take`'s
      derived-combinator convention.
- [x] **T3.2 — Optional operator.**  A parsec-style operator alias *if*
      recognized (per CODE_GUIDELINES long-name/operator rule); otherwise
      long names only.

## Phase 4 — Tests + coverage

- [x] **T4.1 — Roundtrip anchors.**  Anchor the new roundtrip + bound lemmas
      (and a `satisfy_many1 is_token_char` concrete vector) in
      `test/Data.Codec.Test.Integration.fst` (100% coverage).
- [x] **T4.2 — Coverage audit.**  Run the §9 `lemma_*` two-list `comm` check;
      zero uncovered `lemma_*`.

## Phase 5 — Verify + record

- [x] **T5.1 — Build green.**  `nix build .#checked .#native .#ocaml .#fsharp`
      + `nix flake check` all GREEN; `grep` admits/assume empty in `src/`.
- [x] **T5.2 — Changelog + docs.**  Add the new combinator to `CHANGELOG.md`
      and `API.md`.
- [x] **T5.3 — Update the F\* skill.**  If the generic symbolic-`f` run
      roundtrip reveals a new/refined lesson vs `fstar-proofs` §11/§60 (the
      "prove §11 bridges *inside the defining module*, not at the consumer"
      placement rule), record it in the skill before closing.

## Out of scope (recorded)

- `fstar-mime` rewire — a separate change that consumes this combinator via the
  `fstar-codec` flake dep (replaces its bespoke `token_run_scan`/
  `mime_bytes_enc`/`mime_bytes_dec`).
- Generalizing `take_until`/`one_of` into generic-`codec` roundtrips.
