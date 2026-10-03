# codec — verified bidirectional codec library

A formally verified, bidirectional serialization framework in
[F\*](https://www.fstar-lang.org/).  **Twenty combinators, zero admits,
every proof mechanically checked.**

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
convention, and the leaf codecs are **Pulse**, so the same verified definitions
compile to C for use at the byte-buffer level.

## Features

- **One verified type.**  A single `codec a` record: `enc`, `dec`,
  a well-formedness guard, and a roundtrip lemma field.
- **Twenty combinators.**  Primitives (`token`, `byte_val`, `satisfy`, `pure`,
  `text`, `bytes`, `uint8`, `word16be`, `word16le`, `word32be`, `word32le`,
  `varint`, `digits_to_int`) plus combinators (`custom`, `product`, `sum`,
  `map_`, `count`, `label`, `alt`), and the operator aliases (`<|>`, `*>`, `<*`).
  The ad-hoc helpers `one_of` and `take_until` return (enc, dec, wfcv) triples,
  not `codec` records.
- **Proven roundtrips.**  Every combinator carries a lemma; no `admit`, no
  `assume`, no `admit_smt_queries` (the anchor test module uses a scoped,
  semantically-neutral `--admit_smt_queries true` — see `AGENTS.md`).
- **C extraction.**  The Pulse leaf codecs extract to C with byte-level
  post-conditions.
- **A real test suite.**  121 roundtrip and error-path tests (111 pure + 10
  Pulse buffer tests), all verified.

## Modules

| Module | Role |
|--------|------|
| `Data.Codec.Types` | The `codec a` record, the base combinators, their lemmas. |
| `Data.Codec` | Derived combinators, operator aliases, character predicates. |
| `Data.Codec.Pulse` | C-extractable leaf codecs (8 types), buffer I/O, roundtrip lemmas. |

Test modules (verified, not extracted):

| Module | Role |
|--------|------|
| `Data.Codec.Test.Roundtrip` | Pure roundtrip and error-path property tests. |
| `Data.Codec.Test.Pulse` | Buffer-based roundtrip + error tests for the Pulse leaf. |
| `Data.Codec.Test.Integration` | Binds every test + lemma, enforcing coverage. |

## Getting started

```bash
# Default: build the native (C11) shared/static library of the Pulse leaf.
nix build

# The four targets
nix build .#checked    # F* verification gate (0-admit: spec + leaf + tests)
nix build .#ocaml      # OCaml findlib package of the pure spec + Pulse leaf
nix build .#native     # C11 shared/static lib (default)
nix build .#fsharp     # .NET library

# Dev loop (no nix): verify via the Makefile
nix develop && make check
```

`nix build` with no argument builds the default package,
`native` (the C11 shared/static library).  The authoritative verification gate
is `nix build .#checked`; the LSP is a dev-loop aid, not a substitute.

The build is three layers:

| File | Responsibility | Works without flakes? |
|------|----------------|-----------------------|
| `flake.nix` | inputs/outputs + `devShell` | no (needs flakes) |
| `default.nix` | builds `checked` / `ocaml` / `native` / `fsharp` | yes (`nix-build` / `import`) |
| `Makefile` | the shell-script verify (module order) | yes (plain `fstar` on PATH) |

Toolchain: F\* `v2026.09.20+lsp` (a fork pin carrying the LSP server).
`Data.Codec.Pulse` is the Pulse leaf (8 leaf codecs + dispatch + roundtrip
lemmas) that compiles to C11, OCaml, and F#.

## Architecture

```
Data.Codec.Types     — codec record, 22 combinators, all lemmas
Data.Codec           — derived combinators, operator aliases, char predicates
Data.Codec.Pulse     — C-extractable leaf codecs (Pulse fn, C/OCaml/F# output)
```

## License

**Dual-licensed.**  [AGPL-3.0-or-later](LICENSE.md), **or** a commercial
license is available from the author.  See [LICENSE.md](LICENSE.md) — the
commercial-license terms are at the top.

## Author

[Dysinger](https://github.com/dysinger)
