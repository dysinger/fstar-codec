# codec — verified bidirectional codec library

A formally verified, bidirectional serialization framework in
[F\*](https://www.fstar-lang.org/).  **Every proof mechanically checked, zero
admits, one description for both directions.**

## What it is

`Data.Codec` gives you one type for both directions of a format: a `codec a` is
a value that knows how to **encode** an `a` to bytes, **decode** bytes back to
an `a`, and carries the **roundtrip proof** that

```text
decode (encode x ++ rest) == (x, consumed = |encode x|)
```

A parser and a printer stop being two separate programs that can drift apart;
they become two halves of a single value that F\* guarantees stay in lockstep.

**Stated precisely, because the difference matters:** the guarantee is that
decoding the *encoding of a value* recovers that value — conditional on the
codec's domain and on the continuation, as `[D9]` and `[W1]` record.  It is not
a total `decode ∘ encode = id`.  The proof lemmas are erased before extraction,
so the check costs nothing at runtime.

## Motivation

A wire format is really one specification with two directions, but we almost
always write it as two programs — a parser and a printer — maintained side by
side.  The moment they disagree, you get silent corruption: a field the printer
writes but the parser skips, an offset off by one, a terminating case one side
forgets.

`Data.Codec` makes the disagreement impossible to write.  You express the format
once, as a composition of combinators, and F\* *proves* — not merely tests — that
encoding and decoding are inverses.

## Where the idea comes from

This library implements **invertible syntax descriptions**, introduced by
Tillmann Rendel and Klaus Ostermann in

> [*Invertible Syntax Descriptions: Unifying Parsing and Pretty Printing*](https://doi.org/10.1145/1863523.1863524) — Rendel & Ostermann, 2010.

Their insight: a grammar can be a *single* value that both parses and
pretty-prints, removing the class of bugs born from keeping two programs in sync.

The paper states the inverse invariant in prose and says so itself — §5: a
partial isomorphism written directly "is not safe because **it is not checked
that the two directions are really inverse to each other**".  §7.5 leaves the
follow-up open: *"It would be interesting to see **how the invariants of `Iso`
values could be encoded in a dependently typed language**"*.

**This library answers §7.5 for F\***: the inverse law is a **field**, so a codec
without its proof cannot be constructed.  Doing so required **eleven** departures
from the paper, bought **seven** strengthenings, and cost **seven** explicitly
given-up guarantees.  All three lists are below, in full, because a codec that
only advertises its wins is not auditable.

---

## The delta with the paper

This is the complete record of every place this library departs from Rendel &
Ostermann (§-cited), what it proves that the paper does not, and what it gives
up.  Anchors are stable cross-reference targets.

**One fact explains most of the list: this library has three interpreters for one
description — a specification the SMT solver reasons about, an executable model
produced by OCaml extraction, and a C program extracted by Custard through Pulse
over fixed buffers.**  The third is the binding constraint: `[D2]`, `[D5]`,
`[D6]`, `[D9]`, `[D10]` and `[D11]` all trace to a fact about C — no closures, no
sum types, no allocation, `u32` offsets over a caller-owned buffer.  Dropping any
*other* interpreter would not relax one of them.

### Departures (observable-semantics changes)

| | Departure | Why |
|---|---|---|
| **[D1]** | `String`/`Char` → **bytes** | §4.1's syntax is textual. A binary format is not made of characters; many bytes are not printable. `token : codec byte` is the paper's `token` on a byte carrier, and text is rebuilt downstream, on top of bytes. |
| **[D2]** | a **single-answer** decoder | §4.3's decoder returns *every* parse. This one returns `either decode_error (a & nat)` — one answer or an error — because the decoder is the one Custard extracts: a list per parse is an allocation on the hot path with no lowering to a buffer-and-cursor, and §4.4 already admits backtracking's exponential cost. **Cost:** the guarantee given up is `[W4]`. |
| **[D3]** | `alt` **selects from the input** | With one answer, both branches cannot be tried, so `alt` takes `p1 : byte -> bool`. The paper is already asymmetric — parser `|` is backtracking union (§4.1), printer `|` is left-biased `mplus` (§4.2); this keeps one direction of each. The obligation is stated in the type (`[S3]`). |
| **[D4]** | **no `ignore`** | §6.3's `ignore :: α → Iso α ()` — "not a strict partial isomorphism, because all values of `α` are mapped to ()". The `roundtrip` field cannot be discharged by a constant encoder, so the combinator cannot be written. A run of bytes is *captured* and re-emitted verbatim. Where the paper relaxes the law to keep a destructive constructor, this library keeps the law and drops the constructor. |
| **[D5]** | `codec` is a **record of functions**, not §3.4's typeclass | Projection fields normalise under SMT, which is what discharges 27 roundtrips with no induction, and a record lowers where an AST with function-valued leaves does not (`[D11]`). **Cost:** opacity ⇒ accessor lemmas and per-combinator solver lemmas (`[W2]`). |
| **[D6]** | `enc` is **total**; well-formedness is a `bool` *and* a `prop` | The guard must be reachable from a runtime check: the C caller discharges `pure (U32.v v < 65536)` in a Pulse precondition, and a `prop` is erased before it reaches the checker. A second field then exists so the *proof* can consume the same fact. **Cost:** `[W3]`, and the redundancy in `[W1]`. |
| **[D7]** | `dec` reports **consumed bytes**, and `remainder` is the fix | `(value, nat)` trusts a claimed count that `dec_consumed_bound` repairs by lemma. `remainder s = r:byte_seq{ \|r\| ≤ \|s\| }` carries the bound in the type, so consumers get it free and the bound becomes structural (`[S2]`). Load-bearing: without it `product` inherits an undischargeable `\|r₁\| ≤ \|s\|`. |
| **[D8]** | `codec` and `codec_v2` **coexist** during migration | The two cannot share a name while 27 `roundtrip` fields migrate one at a time. `_v2` is a **temporary** label; the end state renames it back. Placement is constrained: `codec_v2` must be declared *after* `sep_by1_opt_trailing_roundtrip`, or that lemma's obligation becomes unprovable (`Error 19`; rlimit 1600 does not help). |
| **[D9]** | the laws are **conditional** | The central departure. See the dedicated section below. |
| **[D10]** | the carrier is **`Seq byte`** plus a refined remainder | Three independent reasons: `Seq` has 93 lemmas behind it, so laws reduce; Custard consumes `Pulse.Lib.Array.array U8.t` through `pts_to` views and `u32` offsets, so a `Seq` can never be the runtime carrier; and every Pulse post-condition and downstream consumer is already stated over `Seq byte`. **Consequence:** the specification carrier and the runtime carrier are two objects, and the obligation is to prove they agree. |
| **[D11]** | a **closed 8-leaf GADT** for C | Custard emits C with no closures and no `Prims.int`; a record holding `a -> option byte_seq` does not translate. `decode_bytes` takes a tag, not a codec, and every `fn` carries a byte-level separation-logic post-condition proved to agree with the pure spec. The source states the exclusion rule: *"`CT_Satisfy` excluded: function-typed constructor breaks extraction. `CT_Bytes`, `CT_Text` excluded: use the pure-spec bridge."* **Cost:** `[W6]`. |

### [D9] in full — why the law is conditional

The paper's inverse law is unconditional, because §3.1 leaves it in prose and
§6.3 relaxes it to "modulo equivalence classes" whenever a destructive
constructor appears.  Here the law is a **field** *and* carries three hypotheses:

```fstar
roundtrip : (v: a) -> (r: byte_seq) -> Lemma
  (requires wfcv v /\ wfcv_prop v /\ rest_cond v r)
  (ensures dec (enc v `Seq.append` r) == Inr (v, Seq.length (enc v)));
```

Each hypothesis is the F\* encoding of a fact the paper's design supplies
otherwise:

| the paper supplies it by | this library must state it | because |
|---|---|---|
| returning **every** answer (§4.3), so the correct one is always present | `rest_cond` | a single-answer decoder can select the greedy answer that over-consumes `r` |
| `apply : α → Maybe β`, partial **by type** | `wfcv` | the C caller needs a runtime-checkable `bool`, not an erased `prop` |
| the type of `Iso` itself | `wfcv_prop` | the proof needs the proposition the `bool` decides |

**What `[D9]` is not.** The paper's escape hatch is equivalence classes (§3.1:
"we will sometimes interpret this condition modulo equivalence classes").  This
library does **not** take that route: the constructor that would need it is
absent (`[D4]`), and the three hypotheses are *exact* conditions — a specific run
must not extend, a specific value must be in range — not classes.  A conditional
law whose conditions are precise is a different object from a law relaxed to hold
"up to" a quotient.

### Strengthenings (what this library proves that the paper does not)

An entry belongs here only if it adds a fact the paper **does not state or does
not check**.

| | Strengthening | Basis |
|---|---|---|
| **[S1]** | the inverse law is **enforced by the type** — the answer to §7.5 | A codec without its proof cannot be constructed. Claims *enforcement*, not *unconditionality*: a conditional obligation the compiler demands is strictly more than an unconditional claim nothing checks, but it is not the same thing (`[W1]`). |
| **[S2]** | the consumed-byte bound is **structural** | Under `remainder` (`[D7]`) it follows from `dec s = Some (v, r)` by type. Previously a field on every codec, every instance `(fun s -> ())` — dead weight that proved nothing. |
| **[S3]** | branch selection is **stated in the type** | `alt_wfcv` is discharged once, in the constructor, not re-derived per call site or left implicit. Strengthens over *silence*; its existence is a cost of `[D3]` (`[W4]`). |
| **[S4]** | `codec` quantifies over **`eqtype`** | Makes the roundtrip a *decidable* proposition the solver can work with. A restriction that strengthens the specification; free in practice, since every downstream value type is `string`/`int`/`byte` records. |
| **[S5]** | a **facade with two naming layers** | Long names (`then_drop`) *and* operator aliases (`*>`), per `CODE_GUIDELINES.md`; `Data.Codec` uses `include` **and** `open` so both reach consumers. |
| **[S6]** | **93 lemmas, mechanically anchored** | Every `lemma_*` is anchored by name in `Data.Codec.Test.Integration`, so deleting one breaks verification; 34 `_co*` bindings anchor values too. The paper, being prose plus listings, has no equivalent guarantee. Coverage is *not* total — see `[W7]`. |
| **[S7]** | the stopping condition is **exact and direction-split** | `codec_v2` gives `law_fwd` a value-indexed `rest_cond_v` (it holds the value) and `law_bwd` nothing (the value is what it recovers). A single shared predicate is *circular*; splitting dissolves it, and it is what lets `sep_by1`'s forward law thread as conjunction elimination instead of an unprovable prefix-closure step. |

### Weaknesses (what this library gives up)

Each entry is a **loss of guarantee** against the paper, with the reason it was
accepted.  The reasons are real — the C path, the extraction model, a
single-answer decoder — but a real reason makes a trade honest; it does not make
the result a strengthening.

| | Weakness | Consequence |
|---|---|---|
| **[W1]** | the inverse law is **conditional**, and redundant in one place | "Invertible" becomes a property of the description *on a domain the caller supplies*. Of the three hypotheses only `wfcv_prop` is *purely* a cost — it exists solely to mirror `wfcv`; `wfcv` drives a real runtime check and `rest_cond` a real stopping condition. `codec_v2` removes `wfcv_prop`. |
| **[W2]** | invertibility is **solver-borne**, not structural | "All codecs are invertible" is a **27-lemma family**, not one argument, and each lemma is sensitive to `--z3rlimit` and `--fuel`. A reader cannot verify the claim by reading a proof. AUDIT §4 — **not resolved**. |
| **[W3]** | `enc` is **total**, so an out-of-domain value yields a wrong answer, not an error | `uint8.enc 1000` yields `0xE8` (`v % 256`). The type no longer prevents the mistake: a caller that ignores `wfcv` gets silent corruption. `codec_v2`'s `enc : a -> option byte_seq` is the fix, and is what the migration lands. |
| **[W4]** | **no backtracking**: `alt` needs a caller-supplied discriminator | A description that cannot be told apart from its first byte cannot be expressed at all, and the paper's `many` has no analogue of the same shape (`count`, `satisfy_many*`, `sep_by1*`, `take_until` cover the cases, each needing an explicit bound or terminator). The paper's own §4.4 cost — exponential worst case, space leak — is avoided. |
| **[W5]** | `map_`'s backward law needs an **extra obligation** | `map_retract_on_image`, quantified over the codec's image rather than universally. Not derivable: a law-abiding codec plus concrete `(f, g)` refute it outright. Forced by `[D5]`'s record shape; a value-dependent law cannot be a field. |
| **[W6]** | the C path covers **8 leaves**, not the library | `product`, `alt`, `sep_by1*`, `take_until`, `opt_prefixed`, `satisfy_many*` have a pure spec and **no C path**. "The library extracts to C" is true of the leaves only. |
| **[W7]** | **one combinator lacks a coverage anchor** | `opt_prefixed` has no `let _x = opt_prefixed` in the integration module, so renaming or deleting it would leave the build green. |

### [O1] — recorded and **rejected**: no benefit under a C-only product goal

**[O1] A dual carrier** — `dec_spec : byte_seq -> list (a & remainder s)` (every
answer, making the law unconditional) alongside `dec_run : byte_seq -> option (a
& remainder s)` (the single answer the runtime uses), with a proved relation
between them.  This is the only known route to an unconditional law (`[W1]`)
while keeping C.

It doubles the combinator surface, adds a bridge obligation per node, and its
risk is that the "which answer did we pick" fact is **unprovable**, not merely
unproved.

**Verdict: rejected for this library's delivery goal.**  The benefit `[O1]` buys
is a purely specification-side guarantee — an unconditional law.  No C consumer
can observe it: `[W6]` already bounds what the C tier covers, and the C artifact
is unchanged by whether `dec_spec` returns a list.  Paying a doubled surface and
a per-node bridge for a guarantee the product cannot exhibit is the wrong trade.

It remains recorded so the gap against the paper is a **decision, not an
omission** — and so the route is available if the goal ever becomes
"specification parity with the paper" rather than "a verified codec that
compiles to C".

### Compatibility note

`Data.Codec.Pulse`'s `decode_result_c` is a **C-compatible** discriminated union
(`DR_Inl`/`DR_Inr` over a single boxed `U32.t`), not the pure layer's
polymorphic `either`.  This is deliberate: C has no sum types, so every scalar
leaf decodes into the same `U32.t` slot.  Do **not** refactor it to an
`either`-based polymorphic sum — that breaks `.#fsharp` and `.#native`
extraction.

---

## Features

- **One verified type.**  A single `codec a` record: `enc`, `dec`, a
  well-formedness guard, and a `roundtrip` lemma field.
- **26 combinators.**  Primitives (`token`, `byte_val`, `satisfy`, `pure`,
  `bytes`, `uint8`, `word16be`, `word16le`, `word32be`, `word32le`, `varint`,
  `digits_to_int`, `text`) plus combinators (`custom`, `product`, `sum`, `map_`,
  `count`, `label`, `alt`), the variable-width predicate runs (`satisfy_many0`,
  `satisfy_many1`), and the separator family (`sep_by1`, `sep_by1_trailing`,
  `sep_by1_opt_trailing`, `opt_prefixed`) — plus operator aliases (`<|>`, `*>`,
  `<*`).  `one_of` and `take_until` return `(enc, dec, wfcv)` triples, not
  `codec` records.
- **93 lemmas, 0 admits.**  No `admit`, no `assume val`.  (`AUDIT.md` owns the
  maintained recount of combinator and lemma counts.)
- **C extraction.**  The Pulse leaf codecs extract to C11 with byte-level
  post-conditions, proved to agree with the pure spec.
- **A real test suite.**  121 pure roundtrip/error-path tests plus 10 Pulse
  buffer tests, all verified.
- **A strict-isomorphism core type in progress.**  `codec_v2` makes the two
  directions *mutually* constraining (`law_fwd` + `law_bwd`) instead of a one-way
  conditional roundtrip.  Spike-proved for `token`, `product`, `alt`, `sum`,
  `sep_by1`, positional `count`, `map_` and a greedy run codec — but **no
  combinator uses it yet**; see `openspec/changes/codec-strict-isomorphism`.

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
C dispatcher (`codec_t`) names them directly through
`module DC = Data.Codec.Types`; separating them requires splitting that
dispatcher.  See `AUDIT.md` §2/§2a.

Test modules (verified, not extracted):

| Module | Role |
|--------|------|
| `Data.Codec.Test.Roundtrip` | Pure roundtrip and error-path property tests (121). |
| `Data.Codec.Test.Pulse` | Buffer-based roundtrip + error tests for the Pulse leaf (10). |
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

`nix build` with no argument builds the default package, `native` (the C11
shared/static library).  The authoritative verification gate is
`nix build .#checked`; the LSP is a dev-loop aid, not a substitute.

The build is three layers:

| File | Responsibility | Works without flakes? |
|------|----------------|-----------------------|
| `flake.nix` | inputs/outputs + `devShell` | no (needs flakes) |
| `default.nix` | builds `checked` / `ocaml` / `native` / `fsharp` | yes (`nix-build` / `import`) |
| `Makefile` | the shell-script verify (module order) | yes (plain `fstar` on PATH) |

Toolchain: F\* `v2026.09.20+lsp`.  `Data.Codec.Pulse` is the Pulse leaf (8 leaf
codecs + dispatch + roundtrip lemmas) that compiles to C11, OCaml, and F#.

**On the four targets.**  `checked` is the verification gate and uses **no
`--codegen` at all**; `make check` likewise writes only `out/checked`.  The
`native` (C) and `fsharp` derivations build directly from `checked` — neither
depends on `ocaml` or `ocaml-src`, which are independent packaging derivations.
So the OCaml target is a **by-product of verification**, not a step in the C
path: dropping it would remove a dune package and change nothing about the C
artifact.  It is kept because it is the only *executable* model of the pure
spec — the C tier covers 8 leaves (`[W6]`), so OCaml is how a composite codec
such as `product`/`sep_by1` can be run to see its actual bytes.

## Architecture

```
Data.Codec.Types     — format-agnostic core: codec record, combinators, lemmas
Data.Codec.Text      — ASCII text leaves + character predicates
Data.Codec           — facade (include Types + Text) + derived combinators
Data.Codec.Pulse     — C-extractable leaf codecs (Pulse fn, C/OCaml/F# output)
```

## License

**Dual-licensed.**  [AGPL-3.0-or-later](LICENSE.md), **or** a commercial
license is available from the author.  See `LICENSE.md` — the commercial-license
terms are at the top.

## Author

[Dysinger](https://github.com/dysinger)
