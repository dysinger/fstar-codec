# fstar-codec

A formally verified, bidirectional serialization framework in
[F\*](https://www.fstar-lang.org/).  **19 combinators, zero admits, every
proof mechanically checked** — and the Low\* leaf codecs extract to C via
[KaRaMeL](https://fstarlang.github.io/karamel/).

`Data.Codec` gives you a single, verified `codec a` type: a value that knows
how to **encode** an `a` to bytes, **decode** bytes back to an `a`, and carries
the **roundtrip proof** that `decode (encode x) == x`.  Build parsers and
serializers from composable combinators instead of hand-written scanners.

## Why

Bidirectional codecs are easy to get subtly wrong: a parser and printer drift
apart, an offset is off by one, an error path is unhandled.  `Data.Codec`
eliminates that class of bug.  Every combinator ships its roundtrip lemma, so
the F\* typechecker proves — not merely tests — that what you encode is what
you decode.

## Features

- **One verified type.**  A single `codec a` record with `enc`, `dec`,
  well-formedness guards, and a roundtrip lemma field.
- **19+ combinators.**  Primitive codecs (`byte`, `u16`, `u32`, …), `seq`,
  `sum`, `product`, `fixed`, `counted`, `map_`, `alt`, `one_of`, `take_until`,
  `many`, `many1`, `optional`, `choice`, and the operator aliases (`<|>`,
  `*>`, `<*`, `>>=`).
- **Zero admits.**  Proofs discharge through SMT or a stdlib lemma — no
  `admit`, no `assume`, no `admit_smt_queries`.
- **C extraction.**  The Low\* leaf codecs extract to C via KaRaMeL with
  byte-level post-conditions.
- **Concrete test suite.**  120 roundtrip and error-path tests, all verified.

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
# Build (verify + KaRaMeL extraction of the .Low module)
nix build

# Specific targets
nix build .#fstar-codec-checked   # F* verification only
nix build .#fstar-codec-krml      # KaRaMeL extraction (depends on checked)

# Dev loop
nix develop
make check    # verify src/ + test/
make krml     # extract out/krml/*.krml
make clean
```

`nix build` (no argument) builds the default package, `fstar-codec-krml`.

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
