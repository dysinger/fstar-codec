# fstar-codec

A formally verified, bidirectional serialization framework in
[F\*](https://www.fstar-lang.org/).  **Nineteen combinators, zero admits,
every proof mechanically checked** — and the Low\* leaf codecs extract to C via
[KaRaMeL](https://fstarlang.github.io/karamel/).

## What it is

`Data.Codec` gives you one type for both directions of a format: a `codec a` is
a value that knows how to **encode** an `a` to bytes, **decode** bytes back to
an `a`, and carries the **roundtrip proof** that

```text
decode (encode x) == x
```

for every well-formed `x`.  A parser and a printer stop being two separate
programs that can drift apart; they become two halves of a single value that
F\* guarantees stay in lockstep.

## Motivation

A wire format is really one specification with two directions, but we almost
always write it as two programs — a parser and a printer — maintained side by
side.  The moment they disagree, you get silent corruption: a field the printer
writes but the parser skips, an offset off by one, a terminating case one side
forgets.

`Data.Codec` makes the disagreement impossible to write.  You express the
format once, as a composition of combinators, and F\* *proves* — not merely
tests — that encoding and decoding are inverses.  The proof lives in the type,
so any downstream package that builds a parser from these combinators gets the
roundtrip guarantee for free, at zero runtime cost (the lemmas are erased
before extraction).

## Where the idea comes from

This library descends from **invertible syntax descriptions**, first described
by Tillmann Rendel and Klaus Ostermann in

> [*Invertible Syntax Descriptions: Unifying Parsing and Pretty Printing*](https://doi.org/10.1145/1863523.1863524) — Rendel & Ostermann, 2010.

Their insight was that a grammar can be a *single* value that performs both
parsing and pretty-printing, removing the class of bugs born from keeping the
two in sync by hand.  `Data.Codec` takes that idea and strengthens it in two
ways: the language is F\*, so the inverse property is a **proof** rather than a
convention, and the leaf codecs are **Low\***, so the same verified definitions
compile to C for use at the byte-buffer level.

## Features

- **One verified type.**  A single `codec a` record: `enc`, `dec`,
  a well-formedness guard, and a roundtrip lemma field.
- **Nineteen combinators.**  Primitives (`byte`, `u16`, `u32`, …) plus `seq`,
  `sum`, `product`, `fixed`, `counted`, `map_`, `alt`, `one_of`, `take_until`,
  `many`, `many1`, `optional`, `choice`, and the operator aliases (`<|>`,
  `*>`, `<*`, `>>=`).
- **Proven roundtrips.**  Every combinator carries a lemma; no `admit`, no
  `assume`, no `admit_smt_queries`.
- **C extraction.**  The Low\* leaf codecs extract to C with byte-level
  post-conditions.
- **A real test suite.**  120 roundtrip and error-path tests, all verified.

## Modules

| Module | Role |
|--------|------|
| `Data.Codec.Types` | The `codec a` record, the base combinators, their lemmas. |
| `Data.Codec` | Derived combinators, operator aliases, character predicates. |
| `Data.Codec.Low` | C-extractable Low\* leaf codecs (8 types), buffer I/O. |

Test modules (verified, not extracted):

| Module | Role |
|--------|------|
| `Data.Codec.Test.Roundtrip` | Roundtrip and error-path property tests. |
| `Data.Codec.Test.Integration` | Binds every test + lemma, enforcing coverage. |

## Getting started

```bash
# Build: verify src/ + test/, then extract the .Low module to KaRaMeL IR.
nix build

# Individual targets
nix build .#fstar-codec-checked   # F* verification of src/ + test/
nix build .#fstar-codec-krml      # KaRaMeL extraction (depends on checked)

# Interactive checking via the editor LSP (fstar.exe --lsp on PATH)
nix develop
```

`nix build` with no argument builds the default package, `fstar-codec-krml`.
The authoritative verification gate is `nix build .#fstar-codec-checked`; the
LSP is a dev-loop aid, not a substitute.

## Architecture

```
Data.Codec.Types     — codec record, 19 base combinators, all lemmas
Data.Codec.Low       — C-extractable leaf codecs, buffer I/O, dispatch
Data.Codec           — derived combinators, operator aliases, char predicates
```

## License

**Dual-licensed.**  [AGPL-3.0-or-later](LICENSE.md), **or** a commercial
license is available from the author.  See [LICENSE.md](LICENSE.md) — the
commercial-license terms are at the top.

## Author

[Dysinger](https://github.com/dysinger)
