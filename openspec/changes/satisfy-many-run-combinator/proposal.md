# Change Proposal: satisfy-many-run-combinator

## Summary

Add a **variable-width run** combinator to `Data.Codec`:

- `satisfy_many0 (f: byte -> Tot bool) : codec (list byte)` — zero-or-more bytes
  satisfying `f`.
- `satisfy_many1 (f: byte -> Tot bool) : codec (list byte)` — one-or-more bytes
  satisfying `f`.

Both ship a **generic** (symbolic-`f`) roundtrip proof, plus error-position and
consumed-length bound lemmas, in `Data.Codec.Types`.  `satisfy_many1` is the
"one-or-more" form mime needs; `satisfy_many0` rounds out the parser-combinator
set (`many`/`some`) with a zero-base.

## Motivation

The library has `count n c` (fixed-width repetition), `token`/`satisfy`
(single byte), `take n` (= `count n token`), and `take_until` (a
*delimiter*-terminated content run that is **not** a `codec` — it returns an
ad-hoc triple and ships no generic roundtrip, by its own NOTE).  What is
missing is the fundamental **"consume while a predicate holds"** primitive:

```text
run ::= byte₁ … byteₙ   where  f byteᵢ   and   not (f (next byte after byteₙ))
```

Three concrete consumers need it **now**:

1. **`fstar-mime`** — `type "/" subtype` per RFC 2045 §5.1, where `type` and
   `subtype` are runs of token characters (`is_token_char`).  Today `fstar-mime`
   works around the gap with bespoke `token_run_scan`/`mime_bytes_enc`/
   `mime_bytes_dec` — a **Mandate-22 violation** (bypassing the codec layer
   instead of extending it).  This combinator is the correct fix: `mime_codec
   : codec mime` becomes `equiv_map` over `product (satisfy_many1 is_token_char)
   (drop_then (byte_val 0x2F) (satisfy_many1 is_token_char))`.
2. **`fstar-text`** and the layer-2 text/binary packages (`http`, `dns` name
   labels, header values, null/line-terminated binary runs) all need the same
   "run until predicate stops" primitive.  It is a **general** building block,
   not a mime special case.

The library already proves the hard part in-tree, concretely: `digits_to_int`
(`Data.Codec.Types`) decodes a variable-length digit run and proves
`lemma_digits_process_list` — a run roundtrip by list induction with the exact
framing condition

```fstar
(Seq.length r = 0 \/ (Seq.length r > 0 /\ not (is_digit (Seq.index r 0))))
```

`lemma_digits_process_list` is that proof, specialized to `is_digit`.
`satisfy_many1` generalizes it from the concrete predicate to a symbolic
`f : byte -> bool`, keeping the same induction and framing.

## Scope

- **In scope**:
  - `satisfy_many0` / `satisfy_many1` in `Data.Codec.Types` as full `codec`
    records with generic roundtrip + `dec_err_bound` + `dec_consumed_bound`
    (a new combinator numbered 23, or folded into the existing numbering).
  - The run scanner as a **top-level `let rec`** over the byte list (via
    `Seq.seq_to_list` at the boundary), mirroring `count_dec_list`/`take_until`
    — **not** a nested `let rec read` (Warning 242, fstar-proofs §2/§24).
  - The framing `rest_cond` = `Seq.length r = 0 ∨ not (f (Seq.index r 0))`,
    threading exactly like `count_rest_cond_list` threads `count_roundtrip_list`.
  - `satisfy_many1` as `map_`-guarded non-empty over `satisfy_many0` (so the
    roundtrip composes with `map_`'s) **or** a direct sibling — decide by which
    proves cleanly at ≤ `--z3rlimit 120`.
  - Long-name aliases + a `some1`/`many` operator (parsec-style) in
    `Data.Codec`, following the `take`/`then_drop` derived-combinator
    convention.
  - Test coverage: roundtrip lemmas anchored in `test/Data.Codec.Test.Integration.fst`
    (100% coverage, per the repo's own coverage-audit note).
- **Out of scope**:
  - `take_until`/`one_of` generalization (they remain ad-hoc triples with
    per-instantiation roundtrips; this change does not retro-fit them).
  - The `mime` rewire itself — that is a **separate `fstar-mime` change** that
    consumes the new combinator via the `fstar-codec` flake dep.
  - Any `fsharp`/`rust`/`wasm` backend work.

## Technical design

The run decoder is a list-level scan (the `take_until` pattern — `Seq.seq_to_list`
once at the boundary, then list recursion where the predicate looks ahead
cleanly):

```fstar
let rec satisfy_run_scan (f: byte -> Tot bool) (bs: list byte)
  : Tot (list byte & list byte) (decreases bs) =
  match bs with
  | [] -> ([], [])
  | b :: tl -> if f b then let (run, rest) = satisfy_run_scan f tl in (b :: run, rest)
               else ([], bs)
```

`dec s = let (run, rest) = satisfy_run_scan f (Seq.seq_to_list s) in Inr (run, length run)`.
`enc xs = seq_of_list xs`.  `wfcv xs = for_all f xs` (`satisfy_many1` adds
`Cons? xs`).  The roundtrip is:

```fstar
let rec lemma_satisfy_run_roundtrip (f: byte -> Tot bool) (xs: list byte) (r: byte_seq)
  : Lemma (requires for_all f xs /\ (Seq.length r = 0 \/ not (f (Seq.index r 0))))
          (ensures dec (seq_of_list xs `Seq.append` r) == Inr (xs, length xs))
```

proved by list induction mirroring `lemma_digits_process_list` (which already
discharges this *for `is_digit`*), with the `Seq.seq_to_list (seq_of_list l ++ s)`
bridge [already proven in `lemma_seq_to_list_of_list_append`] called inside the
defining module where it is transparent.

**The known wall, and why it is solved here and not per-package.**  The
`Seq.seq_to_list (seq_of_list l ++ r) == l @ Seq.seq_to_list r` rewrite (the
§11 barrier that blocked the earlier bespoke attempt) is **transparent inside
`Data.Codec.Types`** (the module that already carries
`lemma_seq_to_list_of_list_append` at `--z3rlimit 2000`).  Placing
`satisfy_many1` in this module is precisely what makes the generic roundtrip
dischargeable — it was not dischargeable from `fstar-mime` because the bridge
is opaque across module boundaries.  This is the same reason `count`/`bytes`
keep their roundtrip proofs in `Data.Codec.Types`, not at consumption sites.

## Risks

- **Symbolic-`f` induction may not auto-discharge.**  `lemma_digits_process_list`
  proves the concrete `is_digit` case; generalizing `is_digit → f` keeps the
  same shape but SMT may need the predicate applied at each cons step.  The
  mitigation is the same `--z3rlimit`-scoped list induction + explicit
  `assert`s already used there (and the `lemma_satisfy_run_scan_self` list lemma
  already verified in the `fstar-mime` spike).
- **`rest_cond` termination framing.**  The roundtrip requires the *suffix* to
  begin with a byte `f` rejects (else the run over-consumes).  For mime this is
  exact (`/` = 0x2F is not a token char; subtype ends at EOF).  Callers with
  ambiguous terminators must supply a non-token separator or a fixed bound —
  document this in the combinator's fsdoc.
- **`dec_err_bound`/`dec_consumed_bound`.**  Trivial (the scanner returns
  `length run ≤ length s`), mirroring `take_until`'s.

## Dependencies

- None external.  Pure `Data.Codec.Types` + `Data.Codec` change; `fstar-mime`
  consumes it afterward as a separate change.

## Definition of done

- `satisfy_many0`/`satisfy_many1` verify 0-admit in `Data.Codec.Types` under
  `--z3rlimit ≤ 120`.
- Generic roundtrip + both bound lemmas discharge for a **symbolic** `f`.
- A `satisfy_many1 is_token_char` roundtrip lemma (or a concrete-vector test)
  anchors in `test/`, 100% coverage.
- `nix build .#checked .#native .#ocaml .#fsharp` + `nix flake check` GREEN.
- No admits / `assume` / `--admit_smt_queries` in `src/`.
