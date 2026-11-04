# codec — verified bidirectional codec library

A formally verified, bidirectional serialization framework in
[F\*](https://www.fstar-lang.org/).  **Twenty-two combinators, zero admits,
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
- **Twenty-two combinators.**  Primitives (`token`, `byte_val`, `satisfy`,
  `pure`, `text`, `bytes`, `uint8`, `word16be`, `word16le`, `word32be`,
  `word32le`, `varint`, `digits_to_int`) plus combinators (`custom`, `product`,
  `sum`, `map_`, `count`, `label`, `alt`), the variable-width predicate runs
  (`satisfy_many0`, `satisfy_many1`), and the separator family (`sep_by1`,
  `sep_by1_trailing`, `sep_by1_opt_trailing`, `opt_prefixed`) — plus the
  operator aliases (`<|>`, `*>`, `<*`).  The ad-hoc helpers `one_of` and
  `take_until` return (enc, dec, wfcv) triples, not `codec` records.
  (⚠ the count is a maintained claim, not a derived one — `AUDIT.md` owns the
  recount.)
- **Proven roundtrips.**  Every combinator carries a lemma; no `admit`, no
  `assume`, no `admit_smt_queries` (the anchor test module uses a scoped,
  semantically-neutral `--admit_smt_queries true` — see `AGENTS.md`).
- **C extraction.**  The Pulse leaf codecs extract to C with byte-level
  post-conditions.
- **A real test suite.**  121 pure roundtrip/error-path tests plus 10 Pulse
  buffer tests, all verified.
- **A strict-isomorphism core type in progress.**  `codec_v2` (alias
  "Amendment 6") makes the two directions *mutually* constraining
  (`law_fwd` + `law_bwd`) instead of a one-way conditional roundtrip.  It is
  defined in `Data.Codec.Types` and fully spike-proved for `token`, `product`,
  `alt`, `sep_by1` and a greedy run codec, but **no combinator uses it yet** —
  see `openspec/changes/codec-strict-isomorphism`.

## Modules

| Module | Role |
|--------|------|
| `Data.Codec.Types` | Format-agnostic core: the `codec a` record, the structural combinators, and the leaves the Pulse dispatcher depends on. |
| `Data.Codec.Text` | ASCII text leaves: `text`, `string_to_bytes`/`string_is_ascii`, the `is_*`/`char_is_*` predicates, `digit_byte`. |
| `Data.Codec` | Facade: `include`s `Types` + `Text`, plus derived combinators and operator aliases. |
| `Data.Codec.Pulse` | C-extractable leaf codecs (8 types), buffer I/O, roundtrip lemmas. |

**Module scope rule.** `Data.Codec.Types` is the *core*: it must not acquire a
dependency on `Data.Codec.Text`, and it holds no text handling.  Anything that
names a character, a string, or an ASCII predicate belongs in `Data.Codec.Text`.
The machine-specific integer/varint leaves still live in core because the Pulse
C dispatcher (`Data.Codec.Pulse`, `codec_t`) names them directly through
`module DC = Data.Codec.Types`; separating them requires splitting that
dispatcher.  See `AUDIT.md` §2/§2a and `lean-codec`'s `[S3]` scope rule.

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
Data.Codec.Types     — format-agnostic core: codec record, combinators, lemmas
Data.Codec.Text      — ASCII text leaves + character predicates
Data.Codec           — facade (include Types + Text) + derived combinators
Data.Codec.Pulse     — C-extractable leaf codecs (Pulse fn, C/OCaml/F# output)
```

## License

**Dual-licensed.**  [AGPL-3.0-or-later](LICENSE.md), **or** a commercial
license is available from the author.  See [LICENSE.md](LICENSE.md) — the
commercial-license terms are at the top.

## Author

[Dysinger](https://github.com/dysinger)
