# Specs: satisfy-many-run-combinator

## ADDED Requirements

### Requirement: Variable-Width Predicate-Run Combinators

**ID**: REQ-CODEC-MANY-001
**Priority**: P1

The system SHALL provide `satisfy_many0` and `satisfy_many1` combinators in
`Data.Codec.Types`, each of type `(byte -> Tot bool) -> codec (list byte)`,
where:

- `satisfy_many0 f` decodes a **zero-or-more** run of bytes satisfying `f`;
- `satisfy_many1 f` decodes a **one-or-more** run of bytes satisfying `f`.

Both SHALL be full `codec` records carrying a **generic** roundtrip proof valid
for a symbolic predicate `f`, plus `dec_err_bound` and `dec_consumed_bound`
lemmas.  The decoder SHALL scan a maximal leading run (stop at the first byte
that `f` rejects, or end-of-input).

#### Scenario: One-or-more token run roundtrip

- **GIVEN** a predicate `f = is_token_char` and a non-empty token list `xs`
- **WHEN** `satisfy_many1 f` encodes then decodes `xs`
- **THEN** the run reconstructs `xs` and consumes exactly `length xs` bytes

#### Scenario: Zero-or-more empty run

- **GIVEN** `satisfy_many0 f`
- **WHEN** the input is empty
- **THEN** it decodes to `([], 0)`

### Requirement: Run Framing (`rest_cond`)

**ID**: REQ-CODEC-MANY-002
**Priority**: P1

The combinator's `rest_cond` SHALL require that the suffix either be empty or
begin with a byte the predicate rejects:

```fstar
Seq.length r = 0 \/ not (f (Seq.index r 0))
```

This SHALL be the precise condition under which the run stops at the encoded
boundary (i.e. does not over-consume into the suffix).  The generic roundtrip
proof SHALL establish, via list induction, that
`dec (seq_of_list xs `Seq.append` r) == Inr (xs, length xs)` whenever `for_all f xs`
(and `Cons? xs` for `satisfy_many1`) and the framing condition hold.

#### Scenario: Framed run does not over-consume

- **GIVEN** a non-empty run `xs` and a suffix `r` whose head `f` rejects
- **WHEN** `satisfy_many1 f` decodes `seq_of_list xs ++ r`
- **THEN** it consumes exactly `length xs`, leaving `r` unconsumed

### Requirement: Compliant Composition Surface

**ID**: REQ-CODEC-MANY-003
**Priority**: P1

The new combinator SHALL be composable with existing record-`codec` combinators
(`product`, `map_`/`equiv_map`, `drop_then`) so that downstream packages (e.g.
`fstar-mime`) build their codecs from combinators only — no bespoke scanners.

#### Scenario: mime_codec is combinator-built

- **GIVEN** `satisfy_many1 is_token_char`
- **WHEN** `mime_codec》 is defined as `equiv_map` over
  `product (satisfy_many1 is_token_char) (drop_then (byte_val 0x2F) (satisfy_many1 is_token_char))`
- **THEN** it is a valid `codec mime` (in the `fstar-mime` repo) with no
  hand-written encode/decode

## MODIFIED Requirements

### Requirement: Combinator Coverage

**ID**: REQ-CODEC-COV-001
**Priority**: P1

All combinators, including the new `satisfy_many0`/`satisfy_many1`, SHALL have
100% proof coverage with zero `admit()`, `magic()`, `assume`, or
`--admit_smt_queries` in `src/`.  The new combinators' roundtrip + bound lemmas
SHALL be anchored in `test/Data.Codec.Test.Integration.fst`.

#### Scenario: No admits

- **GIVEN** the `fstar-codec` source tree
- **WHEN** `grep`'d for `admit`, `assume`, `admit_smt_queries`
- **THEN** the grep SHALL be empty in `src/`
