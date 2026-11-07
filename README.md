# codec

A verified, bidirectional codec library: **one description, two directions.**

`codec` takes Tillmann Rendel and Klaus Ostermann's _"Invertible Syntax
Descriptions: Unifying Parsing and Pretty Printing"_ (Haskell'10, September 30 2010,
Baltimore, Maryland, USA; ACM) and carries it to **F\***, re-based from text
onto **bytes**.

The paper gives the idea: one description drives both decoding and encoding, and
every block in it is a _partial isomorphism_ whose two directions are related by
an inverse law. Implementing that idea in F\* immediately meets a second set of
obligations the paper never faces, because F\* is not only a proof assistant: the
same description must also be an **OCaml model** and a **C program extracted by
Custard through Pulse, over fixed buffers, with no allocation on the hot path**.

The proofs live in the code (`src/`, each declaration documented in place) and
the engineering state in `openspec/`; this document is the **architecture
statement** — the complete record of where `codec` stands relative to the paper,
and why. `PAPER.md` in this directory is a copy of the paper, so the section
numbers cited below resolve without leaving the repository.

---

## The idea, in one breath

The value-level transformations in a syntax description are **partial
isomorphisms** — a box with two doors, `enc` and `dec`, that are each other's
inverse. If you know how to go _into_ the box, you automatically know how to come
back out, because the two doors are the same fact stated twice. So one
description drives **two directions** at once:

- **decode** — bytes in, value out (the parser);
- **encode** — value in, bytes out (the pretty-printer);

and the two directions are _provably_ inverse, not just documented as such.

Where the paper _states_ that inverse law in prose — and §5 names the cost
explicitly, "it is not safe because **it is not checked that the two directions
are really inverse to each other**", with §7.5 leaving the follow-up open: "It
would be interesting to see **how the invariants of `Iso` values could be encoded
in a dependently typed language**" — `codec` makes it a **field of the type**: you
cannot construct a codec without its proof. The proof lemmas are erased before
extraction, so the check costs nothing at runtime.

In F\* the answer cannot be a single unconditional biconditional — the reasons
are `[D2]`, `[D5]` and `[D9]`, and the resulting loss of strength is stated as
`[W1]` rather than folded into the claim.

---

## From the paper to a binary codec

This is the canonical, complete record of every place `codec` departs from the
paper (a _departure_ — an observable-semantics change) or completes it (a
_strengthening_ — no observable-semantics change), plus what it gives up (a
_weakness_ — a loss of guarantee, stated with the reason it was accepted). Each
entry cites the paper's § and the F\* symbol that implements it, so a porter can
read this one list and know exactly what to reproduce. Anchors `[D1]`–`[D13]`,
`[S1]`–`[S9]`, `[W1]`–`[W9]` and `[O1]` are stable cross-reference targets, shared
with the code and the engineering ledger in `openspec/`.

Section numbers below refer to the paper's own sectioning as reproduced in
`PAPER.md` (the paper uses a mix of `§n` and `§n.m`; where a fact lives in a
subsection we cite the subsection).

### Departures (observable-semantics changes)

**[D1] `String`/`Char` → bytes — bytes become the base unit.**
The paper's concrete syntax is textual. The decoder is
`newtype Parser α = Parser (String → [(α, String)])` (§4.1) and the primitive
token is `token` over `Char`; the value graph is `data Rel α = Rel [(α,
String)]` (§4.3). `codec` targets binary, so the base unit is **`byte`**, the
base string is a `Seq byte`, and `token : codec byte` is the paper's `token` on
the new carrier. A binary format is not made of characters — many of its bytes
are not printable at all. Text and Unicode are rebuilt downstream, **on top of**
bytes, never underneath.

**[D2] A single-answer decoder — not the paper's list.**
The paper's decoder returns a _list_ of `(value, remaining)` pairs — every way to
read the input — and `|` is their union (§4.3). This library's decoder returns
**one** answer or an error:

```fstar
type decode_result (a: Type0) = either decode_error (a & nat)   (* (value, consumed) *)
```

The reason is that the decoder has to be the one Custard extracts. A list per
parse is an allocation on the hot path, it has no lowering to a buffer and
cursor, and backtracking costs are exponential — the paper's own admitted cost
(§4.4: "limits its applicability to large inputs"). The extraction contract is a
populated buffer and a `u32` cursor; a returned list is the one shape that cannot
become that. Backtracking is what makes a decoding law unconditional: with every
answer retained, the correct one is always present, so no stopping condition is
needed. With a single answer the decoder may pick a greedy wrong one, and the
loss must be paid explicitly — that payment is `[D9]`, and the guarantee given up
is `[W4]`.

**[D3] `alt` selects a branch from the input.**
Under `[D2]` the two branches cannot both be tried, so the choice must be decided
from the bytes. `alt` therefore takes a discriminator over the first byte:

```fstar
let alt (#a #b: Type) (c1: codec a) (c2: codec b) (p1: byte -> bool) : codec (either a b)
```

The paper treats the two directions asymmetrically — its parser `|` is
backtracking union (§4.1) while its printer `|` is left-biased `mplus` (§4.2).
This library keeps one direction of each: the reader decides from the input (the
printer's left-bias), and the resulting obligation is stated in the type, not
left implicit (`[S3]`).

**[D4] Lossless capture — there is no `ignore`.**
The paper (§6.3) defines `ignore :: α → Iso α ()`, and says so itself: "`ignore`
is again not a strict partial isomorphism, because **all values of `α` are mapped
to ()**". `skipSpace` and `optSpace` are its two direct instantiations, and they
lose the run: three blanks in, a fixed run out.

No `ignore` exists here. The `roundtrip` field requires `dec (enc v ++ r)` to
return `v`, and a constant encoder cannot recover which run it saw, so the
combinator cannot be written. A run of allowed bytes is instead _captured_ as a
value and re-emitted verbatim — same length, same bytes.

Where the paper relaxes the law to keep a destructive constructor, this library
keeps the law and drops the constructor.

**[D5] `codec` is a record of functions, not the paper's typeclass.**
The paper's descriptions are values of a typeclass (§3.4). Here a codec is a
record:

```fstar
noeq
type codec (a: Type) = {
  enc        : a -> Tot byte_seq;                  (* total *)
  dec        : byte_seq -> Tot (decode_result a);  (* one answer or an error *)
  wfcv       : a -> Tot bool;                      (* runtime well-formedness *)
  wfcv_prop  : a -> Tot prop;                      (* its proof mirror *)
  rest_cond  : a -> byte_seq -> Tot prop;          (* continuation condition *)
  roundtrip  : (v: a) -> (r: byte_seq) -> Lemma
    (requires wfcv v /\ wfcv_prop v /\ rest_cond v r)
    (ensures dec (enc v `Seq.append` r) == Inr (v, Seq.length (enc v)));
  dec_err_bound      : ... ;
  dec_consumed_bound : ... ;
}
```

Each field is a _projection_, so `token.enc v` normalises under SMT. That is what
discharges 27 roundtrips with no induction at all, and it is also what makes a
codec usable as a value in extracted code, where an AST with function-valued
leaves does not lower (`[D11]`).

What it costs: a `noeq` record's fields are opaque across module boundaries, so
every combinator needs accessor lemmas (`lemma_map_wfcv`, `lemma_alt_enc`, …),
and the laws are per-combinator solver lemmas rather than one induction over a
structure. That is `[W2]`.

**[D6] `enc` is total; well-formedness is a `bool` and a `prop`.**
The paper's `apply` is a `Maybe`-valued partial function. Here `enc` is total:

```fstar
enc : a -> Tot byte_seq
```

correct only inside `wfcv`. Applied out of domain it emits _something_ —
`uint8.enc 1000` yields `0xE8` through `v % 256`.

The split survives because the guard has to be reachable from a runtime check.
The C caller reaches `encode_uint` with a `U32.t` and discharges `pure (U32.v v <
65536)` in the Pulse precondition, so well-formedness is a fact about **values at
run time**, not only about proofs; a `prop` is erased before it reaches the
checker. Once `wfcv` is a field, a second field exists to let the _proof_ consume
the same fact (`wfcv_prop`, `fstar-proofs` §18).

Honest status: AUDIT §3 is **not** resolved — `wfcv` and `wfcv_prop` are two
encodings of one fact. That redundancy is `[W1]`'s clearest instance, and
`codec_v2` (`[S7]`) removes it.

**[D7] `dec` reports consumed bytes, and `remainder` is the fix.**
The decoder returns `(value, nat)`, the `nat` being claimed-consumed bytes.
`product` re-slices with `Seq.slice s n1 (|s|)` trusting it, and
`dec_consumed_bound` is a separate lemma that repairs the trust. The bound is not
a typing fact anywhere.

The migration replaces the `nat` with a refined remainder:

```fstar
let remainder (s: byte_seq) = r:byte_seq{ Seq.length r <= Seq.length s }
```

The bound is carried **in the type**, so consumers receive it without a
precondition of their own, and `dec_consumed_bound` becomes structural (`[S2]`)
instead of a field. This is load-bearing: without the refinement `product`
inherits an undischargeable `|r₁| ≤ |s|`.

**[D8] Two record types coexist during migration: `codec` and `codec_v2`.**
The two cannot share a name while 27 `roundtrip` fields migrate one at a time.
`_v2` is a **temporary** label; the end state renames it back. Placement is
constrained: `codec_v2` must be declared _after_ `sep_by1_opt_trailing_roundtrip`,
or that lemma's obligation becomes unprovable (`Error 19`; rlimit 1600 does not
help).

**[D9] The laws are conditional: `wfcv`, `wfcv_prop`, `rest_cond`.**
The paper's inverse law is unconditional, because §3.1 leaves it in prose and
§6.3 relaxes it to "modulo equivalence classes" whenever a destructive
constructor appears. Here the law is a **field** _and_ carries three hypotheses:

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
"we will sometimes interpret this condition modulo equivalence classes"). This
library does **not** take that route: the constructor that would need it is
absent (`[D4]`), and the three hypotheses are _exact_ conditions — a specific run
must not extend, a specific value must be in range — not classes. A conditional
law whose conditions are precise is a different object from a law relaxed to hold
"up to" a quotient.

**[D10] The carrier is `Seq byte` plus a refined remainder.**
Three independent reasons: `Seq` has a large lemma library behind it (`FStar.Seq.Base`
and `FStar.Seq.Properties` together export 145 `val`s), so laws reduce; Custard
consumes `Pulse.Lib.Array.array U8.t` through `pts_to` views and `u32` offsets, so
a `Seq` can never be the runtime carrier; and every Pulse post-condition and
downstream consumer is already stated over `Seq byte`. The consequence is that
the specification carrier and the runtime carrier are two objects, and the
obligation is to prove they agree.

**[D11] The C-facing tier is a closed 8-leaf GADT, not the record.**
Custard emits C with no closures and no `Prims.int`; a record holding `a -> option
byte_seq` does not translate. `decode_bytes` takes a tag, not a codec, and every
`fn` carries a byte-level separation-logic post-condition proved to agree with the
pure spec. The source states the exclusion rule: _"`CT_Satisfy` excluded:
function-typed constructor breaks extraction. `CT_Bytes`, `CT_Text` excluded: use
the pure-spec bridge."_ The result is `[W6]`.

**[D12] Leading zeros are padding, not digits — a numeric reader rejects them.**
§6.4's `integer` is `Iso read' show' $ many digit`, where `read'` accepts whatever
`reads` accepts, whole-string:

```haskell
integer :: Syntax δ ⇒ δ Integer
integer = Iso read′ show′ $ many digit
  where read′ s = case [x | (x, "") ← reads s] of
                    []    → Nothing
                    (x:_) → Just x
```

`read′` is written with the **list** decoder and filters to whole-string matches.
`reads "01"` yields `[(1, "")]`, so the paper's `integer` accepts `"01"` and
returns `1` — while `show′ 1 = Just "1"`. Substituting into `Iso`'s field,
`apply a = some b ↔ unapply b = some a`, gives a **false instance**: one input,
two spellings, one output. The paper does not remark on it; §6.3 notes the
`ignore` case only.

**The classification.** A leading zero carries no numeric information: `enc 1` is
`"1"`, and `"01"` is a _lax spelling_, not a second encoding. That makes it
**padding**, and padding is what §6.3's `ignore` exists to consume — "`ignore`
maps _any_ run of whitespace down to a single value", accepted by the paper
"modulo equivalence classes". This library rejects it for the reason it would
reject `" 1"`: the strict reader does not ignore ignorable characters.

**What it costs, and what it does not.**

- `enc` is **untouched**: every in-domain value produces byte-identical output
  (byte-level preservation, `REQ-ISO-PRESERVE`). Only input `enc` could never
  produce stops decoding, and that input is malformed, not a value.
- `law_bwd` is **not weakened** — it becomes _true_, where before it was false.
- Lenient parsing is **not deleted as a capability**: it belongs _outside_ the
  codec, as a separately-proved layer (the `/lean-codec` `decodeNormal` pattern,
  `[D4]` there). This library has not built that layer; `[W9]` records it.
- **Not the same as `ignore`**: `ignore` is unreachable _because it is
  constant_ (`[D4]`). A leading-zero-tolerant reader is reachable — it is a
  partial iso on a laxer input syntax — but it is a **different object** from
  `integer`, with its own (false, if merged into one) law. Keeping them apart is
  the whole point.

**[D13] Numeric readers accept exactly the encoder's image.**
`varint` (LEB128) and `digits_to_int` reject input their encoder never produces —
overlong LEB128 (`[0x80;0x00]` is not `0`; `enc 0 = [0x00]`) and leading zeros.
Without this the backward direction is **false**, not merely unproved, and no
amount of proof work fixes it. `[D12]` is the digit case; this is the general
obligation. Planned/landing: decoder changes verified; both laws **not yet
proved** (`[W8]`). The Pulse/C decoder must be changed in lockstep or the
extracted C disagrees with the pure spec.

### Strengthenings (we complete the paper, without changing its meaning)

**[S1] The inverse law is _enforced by the type_ — the answer to §7.5.**
A codec without its proof cannot be constructed. Claims _enforcement_, not
_unconditionality_: a conditional obligation the compiler demands is strictly more
than an unconditional claim nothing checks, but it is not the same thing
(`[W1]`).

**[S2] The consumed-byte bound becomes _structural_.**
Under `remainder` (`[D7]`) it follows from `dec s = Some (v, r)` by type.
Previously a field on every codec, every instance `(fun s -> ())` — dead weight
that proved nothing.

**[S3] The branch-selection obligation is _stated in the type_.**
`alt_wfcv` is discharged once, in the constructor, not re-derived per call site or
left implicit. Strengthens over _silence_; its existence is a cost of `[D3]`
(`[W4]`).

**[S4] `codec` quantifies over _`eqtype`_.**
Makes the roundtrip a _decidable_ proposition the solver can work with. A
restriction that strengthens the specification; free in practice, since every
downstream value type is `string`/`int`/`byte` records.

**[S5] A facade with _two naming layers_.**
Long names (`then_drop`) _and_ operator aliases (`*>`), per `CODE_GUIDELINES.md`;
`Data.Codec` uses `include` **and** `open` so both reach consumers.

**[S6] _67 lemmas, mechanically anchored_ against deletion.**
Every `lemma_*` is anchored by name in `Data.Codec.Test.Integration`, so deleting
one breaks verification; `_co*` bindings anchor values too. The paper, being prose
plus listings, has no equivalent guarantee. Coverage is _not_ total — see `[W7]`.

**[S7] Direction-split predicates: `rest_cond_v` for `law_fwd` only.**
`codec_v2` gives `law_fwd` a value-indexed `rest_cond_v` (it holds the value) and
`law_bwd` nothing (the value is what it recovers). A single shared predicate is
_circular_; splitting dissolves it, and it is what lets `sep_by1`'s forward law
thread as conjunction elimination instead of an unprovable prefix-closure step.

**[S8] Readers are _canonical by construction_, not by a side condition.**
`[D13]` makes `dec` accept exactly `enc`'s image, so the backward law becomes
_true_ rather than _conditional on the input_. Weakens nothing: it removes
accepted inputs, adds no hypothesis, and shrinks no domain. It is the answer to
the paper's own §6.4 `integer` defect (`[D12]`), which the paper leaves unstated.
Status: decoders verified, laws open (`[W8]`).

**[S9] The paper's `integer` law _failure is named and fixed_.**
§6.4's `integer` accepts `"01"` while `show′ 1 = "1"`, so its `Iso` field is a
false instance — the same defect class as §6.3's `ignore`, which the paper flags
for `ignore` only. This library states it, classifies it (padding, `[D12]`), and
rejects the input, so the law holds where the paper's does not.

### Weaknesses (what this library gives up)

Each entry is a **loss of guarantee** against the paper, with the reason it was
accepted. The reasons are real — the C path, the extraction model, a
single-answer decoder — but a real reason makes a trade honest; it does not make
the result a strengthening.

**[W1] The inverse law is _conditional_, and redundant in one place.**
"Invertible" becomes a property of the description _on a domain the caller
supplies_. Of the three hypotheses only `wfcv_prop` is _purely_ a cost — it exists
solely to mirror `wfcv`; `wfcv` drives a real runtime check and `rest_cond` a real
stopping condition. `codec_v2` removes `wfcv_prop`.

**[W2] Invertibility is _solver-borne_, not structural.**
"All codecs are invertible" is a lemma family, not one argument, and each lemma is
sensitive to `--z3rlimit` and `--fuel`. A reader cannot verify the claim by
reading a proof. AUDIT §4 — **not resolved**.

**[W3] `enc` is _total_, so an out-of-domain value produces a wrong answer
instead of an error.**
`uint8.enc 1000` yields `0xE8` (`v % 256`). The type no longer prevents the
mistake: a caller that ignores `wfcv` gets silent corruption. `codec_v2`'s `enc :
a -> option byte_seq` is the fix, and is what the migration lands.

**[W4] _No backtracking_: `alt` needs a discriminator supplied by the caller.**
A description that cannot be told apart from its first byte cannot be expressed at
all, and the paper's `many` has no analogue of the same shape (`count`,
`satisfy_many*`, `sep_by1*`, `take_until` cover the cases, each needing an
explicit bound or terminator). The paper's own §4.4 cost — exponential worst case,
space leak — is avoided.

**[W5] `map_`'s backward law needs an _extra obligation_.**
`map_retract_on_image`, quantified over the codec's image rather than universally
(`map_law_bwd_on_image` is its proof). Not derivable: a law-abiding codec plus
concrete `(f, g)` refute it outright. Forced by `[D5]`'s record shape; a
value-dependent law cannot be a field.

**[W6] The C execution path covers _8 leaves_, not the library.**
`product`, `alt`, `sep_by1*`, `take_until`, `opt_prefixed`, `satisfy_many*` have a
pure spec and **no C path**. "The library extracts to C" is true of the leaves
only.

**[W7] _One combinator lacks a coverage anchor_.**
`opt_prefixed` has no `let _x = opt_prefixed` in the integration module, so
renaming or deleting it would leave the build green.

**[W8] The `[D12]`/`[D13]` canonical readers are _verified, but their laws are
not yet proved_.**
The two canonical decoders are written and _provably reject_ their witnesses
(`varint` `[0x80;0x00]` -> `None`; `digits_to_int` `"01"` -> `None`), with
canonical forms intact, at default rlimit and 0 admit. But `law_fwd` and `law_bwd`
over the _canonical_ decoders are **open**, and the Pulse/C decoder is **not yet
updated** — so until both land, the C path still accepts what the pure spec would
reject. Stated here rather than buried: recording `[D12]`/`[D13]` as _done_ before
the laws close would be exactly the "prose that outruns the checker" failure this
document exists to avoid.

**[W9] _No lenient input layer_.**
`[D12]` rejects non-canonical digits rather than tolerating them, so a caller that
must accept `"01"` gets an error. The `/lean-codec` `decodeNormal` mechanism
(`[D4]` there) places that toleration _outside_ the `Iso` as a separately-proved
artifact; this library has **not built it**, and building it is bounded by the
normalizer being length-preserving (so a value whose lax spelling differs in
_length_ — `[0x80;0x00]` -> `0` — is not expressible by it at all; that input is
malformed, not a spelling).

### Open problem

**[O1] A dual carrier — list-valued specification, single-answer runtime.**
The only known way to obtain an **unconditional** law (`[W1]` removed) while
keeping the C path is to separate the specification carrier from the runtime one:

- `dec_spec : byte_seq -> list (a & remainder s)` — **every** answer, which makes
  the inverse law unconditional, since the correct answer is always present; and
- `dec_run : byte_seq -> option (a & remainder s)` — the single answer the runtime
  and Pulse use;
- with a proved relation between them on the accepted set.

This is a coherent design, and it is the honest completion of the paper's §4.3
semantics under F\*'s extraction constraints.

**What it costs.** It doubles the combinator surface (two decoders per node), adds
a bridge obligation at every node, and requires that bridge to be stated in a form
the solver actually discharges. The risk that killed earlier attempts was
precisely that the "which answer did we pick" fact is _unprovable_, not merely
unproved.

**Verdict: rejected for this library's delivery goal.** The benefit `[O1]` buys is
a purely specification-side guarantee — an unconditional law. No C consumer can
observe it: `[W6]` already bounds what the C tier covers, and the C artifact is
unchanged by whether `dec_spec` returns a list. Paying a doubled surface and a
per-node bridge for a guarantee the product cannot exhibit is the wrong trade. It
remains recorded so the gap against the paper is a **decision, not an omission** —
and so the route is available if the goal ever becomes "specification parity with
the paper" rather than "a verified codec that compiles to C".

---

## Representations — `Seq byte` plus a refined remainder (the spec substrate)

`codec`'s **specification carrier** is one byte-string type, `Seq byte`. Every law
(`roundtrip`, `law_fwd`, `law_bwd`) is stated and proved over it.

| | **`Seq byte` + `remainder s`** |
|---|---|
| Job | the single _specification_ substrate for every law |
| Shape | `Seq.seq byte`; a **refined suffix** `remainder s` carries the bound (`[D7]`) |
| For the prover | a large `Seq` lemma library behind it (145 `val`s), so laws reduce without unfolding |
| At runtime | **erased**; C uses `Pulse.Lib.Array.array U8.t` + `u32` offsets (`[D11]`) |

**The decision.** A carrier reducible for the solver and a carrier readable by the
extractor are different objects in F\*. The library keeps them separate and proves
they agree, rather than pretending one object can be both.

The three reasons `Seq` is the spec carrier (rather than the `Pulse.Lib.Array`
the C path uses):

1. **`Seq` has a large lemma library behind it** — `FStar.Seq.Base` and
   `FStar.Seq.Properties` export 145 `val`s between them — so the laws reduce with
   `lemma_append_assoc`, `lemma_index_app1`, `lemma_split` and friends, not by
   unfolding a definition.
2. **Custard consumes `Pulse.Lib.Array.array U8.t`** through `pts_to` views and
   `u32` offsets, so a `Seq` can never be the runtime carrier.
3. **Every Pulse post-condition and downstream consumer is already stated over
   `Seq byte`**, so the pure-spec bridge (`[D11]`) has one shape to target.

The consequence, stated in its own entry: the specification carrier and the
runtime carrier are two objects, and the obligation is to prove they agree
(`[D10]`).

---

## Why these choices — the reasoning in lay terms

This section explains the _reasoning_, for a reader who does not write F\* (or who
is porting `codec` to another language). No claim here goes beyond the statement
above; this is the "why", so a non-F\* reader can judge the trade-offs rather than
just copy the names.

### The one big idea first

The paper's core insight is that one _description_ drives _two directions_ by
making every block a **partial isomorphism** — a box with two doors that are each
other's inverse. The paper _says_ the doors are inverse but never _checks_ it.
`codec` turns that promise into a **field**: you cannot build the box without
supplying the proof that the doors undo each other. That one move — from
"documented in prose" to "enforced by the type" — is `[S1]`, and almost every
other choice below is a consequence of making that move _honest_ in F\*, where a
third interpreter (C) constrains what the box may contain.

### `[D2]` + `[D3]` the decoder returns _one_ answer — why that is the central trade

A parser answers "does this input match, and what value does it produce?". A
**backtracking-union** `|` tries _both_ branches and returns _all_ the possible
results — that is the paper's `|` (§4.3), and it is what makes a decoding law
unconditional: with every answer retained, the correct one is always present.

`codec` cannot keep it, because the decoder has to be the one Custard extracts: a
`List (α × Suffix)` per parse is an allocation on the hot path with no lowering to
a buffer and cursor. So the decoder returns **one** answer, and two consequences
follow immediately:

- the choice between branches must come from the input, so `alt` takes a
  discriminator (`[D3]`);
- the decoder may pick a greedy wrong answer, so a _stopping condition_ must be
  stated for the caller to supply — `rest_cond` (`[D9]`).

The cost is `[W4]`: a description that cannot be told apart from its first byte
cannot be expressed at all. In exchange, the paper's own admitted cost — §4.4's
exponential worst case and space leak — is avoided.

### `[D4]` lossless capture — why we cannot follow the paper's destructive constructor

The paper's `ignore` maps _any_ run of whitespace down to a single value and, on
printing, always emits _one_ (fixed) run back. That is one-way loss: three spaces
in, a fixed run out. The paper accepts this and says the inverse law holds only
"modulo equivalence classes".

`codec` cannot do that — not as a preference, but as a consequence of the
isomorphism itself. Every building block is a strict partial isomorphism, and the
inverse law is a _field_ you must supply. A lossy combinator like `ignore` sends
_every_ run of whitespace to the same value, so its `enc` is a constant, and a
constant `enc` cannot satisfy the law for more than one value. So instead of
following the paper's destructive combinator, a run of allowed bytes is
_captured_ and re-emitted verbatim — same length, same bytes. Where the paper
relaxes the law to keep `ignore`, `codec` keeps the law _strict_ and therefore has
no `ignore`.

### `[D5]` a description is a _record_ — why the paper's typeclass is the wrong shape here

In the paper, a description lives _inside the type system_: a typeclass, with "a
parser" or "a printer" chosen by context. `codec` makes it a **record of
functions**, so `token.enc v` is a _projection_ that normalises under SMT.

Two things follow. First, that projection is what discharges 27 roundtrips with
no induction at all — the laws are per-field solver facts, not a structural
recursion. Second, a record lowers to extracted code where an AST with
function-valued leaves does not (`[D11]`). The cost is `[W2]`: a `noeq` record's
fields are opaque across module boundaries, so every combinator needs accessor
lemmas, and "all codecs are invertible" is a lemma family a reader cannot verify
by reading one proof.

### `[D6]` `enc` total, well-formedness a `bool` — why the guard cannot be a `prop`

The paper's `apply` is a `Maybe`-valued partial function; the type is what
confines it. Here `enc` is total and correct only inside `wfcv`, because the
guard has to be reachable from a **runtime** check: the C caller discharges
`pure (U32.v v < 65536)` in a Pulse precondition, and a `prop` is erased before it
reaches the checker. So `wfcv` is a `bool`. The proof then needs the same fact as
a proposition, which is why `wfcv_prop` exists — a redundancy, and `[W1]`'s
clearest instance, which `codec_v2` removes (`[S7]`).

The honest consequence is `[W3]`: an out-of-domain value yields a wrong answer
rather than an error, because `enc` cannot fail.

### `[D7]` `dec` returns a _remainder_, not a count — why the refinement is load-bearing

The legacy decoder returns `(value, nat)`: the `nat` is a _claimed_ consumed count,
and `product` re-slices with it, trusting it. The trust is repaired by a separate
lemma (`dec_consumed_bound`) — a field on every codec, every instance
`(fun s -> ())`, proving nothing.

The migration replaces the `nat` with `remainder s = r:byte_seq{ |r| ≤ |s| }`. The
bound becomes a **typing fact**, so consumers get it without a precondition of
their own, and the per-codec field disappears (`[S2]`). This is not cosmetic:
without the refinement `product` inherits an undischargeable `|r₁| ≤ |s|`.

### `[D10]` why the carrier is `Seq byte` and not the array

A carrier reducible for the solver and a carrier readable by the extractor are
different objects in F\*. `Seq` has a large lemma library, so every law is one of
them;
`Pulse.Lib.Array` is what Custard turns into a `u32`-indexed buffer. Pretending
one object could be both would mean either a spec the solver cannot reduce or a
runtime the extractor cannot emit. The library keeps them separate and owes a
proof that they agree — which is the pure-spec bridge in `Data.Codec.Pulse`.

### `[S1]` the law is a field — why this is the whole point

Covered above: the paper states the gap plainly (an `Iso` "is not safe because it
is not checked that the two directions are really inverse to each other") and
leaves the dependent encoding open in §7.5; `codec` does it — with the caveat
`[S1]` now states, that the law is **enforced** but, because of `[D9]`, **not
unconditional**. The concrete benefit is that _soundness is impossible to forget_:
you cannot construct a broken codec, because the record will not typecheck
without the proof.

---

## The abstraction, in brief

```fstar
(* partial isomorphisms: two directions, one law, carried as a field *)
noeq type codec (a: Type) = {
  enc        : a -> Tot byte_seq;                  (* total; correct on wfcv *)
  dec        : byte_seq -> Tot (decode_result a);  (* one answer or an error *)
  wfcv       : a -> Tot bool;                      (* runtime well-formedness *)
  wfcv_prop  : a -> Tot prop;                      (* its proof mirror *)
  rest_cond  : a -> byte_seq -> Tot prop;          (* continuation condition *)
  roundtrip  : ...
}

(* a description is a record; the combinators below are the fields *)
(*   custom / product / sum / map_ / count / label / alt              (structural) *)
(*   token / byte_val / satisfy / pure / bytes / uint8 / word* / varint / ... (leaves) *)

(* the specification carrier is `Seq byte`, the suffix refined *)
(*   remainder (s: byte_seq) = r:byte_seq{ Seq.length r <= Seq.length s } *)

(* one description, three interpreters over ONE carrier *)
(*   dec  : byte_seq -> decode_result a            (the spec the solver reasons about) *)
(*   enc  : a -> byte_seq                          (the spec) *)
(*   C    : codec_t (8 leaves) -> dr_inl/dr_inr     (Pulse over Pulse.Lib.Array, [D11]) *)

(* the law that makes it a codec, CONDITIONAL ([D9]) *)
(*   (wfcv v /\ wfcv_prop v /\ rest_cond v r) ==> dec (enc v ++ r) == Inr (v, |enc v|) *)
```

The record shape means the roundtrip is **per-combinator solver lemmas**, not one
induction over a structure — that is `[W2]`, and it is the deliberate price of
`[D5]`'s projection convenience and `[D11]`'s extractability.

### Why the law is conditional, in one place

The three hypotheses of `[D9]` are not decoration: each replaces something the
paper gets from a design choice this library could not keep.

- `rest_cond` replaces "the correct answer is always present" — a single-answer
  decoder can over-consume the continuation, so the caller supplies exactly what
  must not be eaten.
- `wfcv` replaces "`apply` is partial by type" — the C caller needs a `bool` it
  can test at run time.
- `wfcv_prop` mirrors `wfcv` for the proof — the redundancy `[W1]` concedes, and
  the one `codec_v2` deletes.

### `codec_v2` — the strict type now in flight

The change `codec-strict-isomorphism` replaces the one-way `roundtrip` (`[D5]`,
`[D9]`) with a strict bidirectional type in which **both** directions are fields:

```fstar
law_fwd : enc x = Some e /\ wfcv x /\ rest_cond_v x r ==> dec (e ++ r) = Some (x, r)
law_bwd : dec s = Some (v, r) ==> exists e. enc v = Some e /\ s == e ++ r
```

**Every structural combinator is proved.** The spike suite verifies **28 modules**
with 0 admits, plus 3 asserted refutations that must fail. Status per combinator:

| Combinator | `law_bwd` | `law_fwd` |
|---|---|---|
| `token`, `byte_val`, `satisfy`, `uint8`, `pure`, `bytes` | ✅ | ✅ |
| `word16be`, `word16le`, `word32be`, `word32le` | ✅ | ✅ |
| `product`, `alt`, `sep_by1`, `sum` | ✅ | ✅ |
| greedy `satisfy_many0` | ✅ | ✅ |
| `count` (positional) | ✅ | ✅ |
| `map_` | ✅ w/ `map_law_bwd_on_image` (the `retract` hypothesis) | ✅ w/ the folded guard |
| `text` | not yet proved (swept canonical, so statable) | not yet proved |
| `varint` | ⛔ **FALSE** over the library's decoder — overlong LEB128 (`[D13]`) | ✅ at full `wfcv = [0, 2^35)` |
| `digits_to_int` | ⛔ **FALSE** over the library's decoder — leading zero (`[D12]`) | — |

**Nothing is migrated into `src/` yet** — `codec_v2` is declared there and proved
in the spike suite, but no combinator in `src/` uses it. `[W8]` is therefore open,
and it stays open until all of the following land:

1. `law_fwd`/`law_bwd` over the two canonical numeral readers (items 3–4 of the
   change's obligation ledger);
2. `Data.Codec.Pulse`'s `varint_decode_expected` canonicalised in lockstep;
3. the extracted C measured rather than estimated.

---

## Scope

- **`codec`** (this package): the pure framework — the `codec` record, the 26
  combinators, the laws, and the C-facing leaf tier. It **does** ship concrete
  leaves (`uint8`, `word*`, `varint`, `digits_to_int`, `text`) because the Pulse C
  dispatcher (`[D11]`) names them directly; that is a departure from the sibling's
  empty-of-leaves core, recorded as `[W6]`'s counterpart.

  | Module | Role | Extracts to |
  |---|---|---|
  | `Data.Codec.Types` | the record `codec a`, all combinators on bytes, 62 lemmas | OCaml only (pure spec) |
  | `Data.Codec.Text` | `text : string -> codec string`, UTF-8/ASCII bridge | OCaml only |
  | `Data.Codec` | facade: re-exports, long-name aliases, operators | OCaml only |
  | `Data.Codec.Pulse` | 8-leaf `codec_t`, the `fn`s and their roundtrip lemmas | **C, OCaml, F#** |

  **67 lemmas, 0 admits.** No `admit`, no `assume val` anywhere in `src/`;
  `make check` verifies **7 modules**.

  **Module scope rule.** `Data.Codec.Types` is the _core_: it must not acquire a
  dependency on `Data.Codec.Text`, and it holds no text handling. Anything that
  names a character, a string, or an ASCII predicate belongs in `Data.Codec.Text`.
  The machine-specific integer/varint leaves still live in core because the Pulse
  C dispatcher (`codec_t`) names them directly through `module DC =
  Data.Codec.Types`; separating them requires splitting that dispatcher (its own
  change: `codec-binary-tier-split`).

- **Downstream (not in this repository)**: the formats this framework is meant to
  carry — numerals, text, network messages. The sibling splits these into
  `lean-basen` and `lean-text`; here the leaves that the C tier needs live in
  core, and the rest are consumer code.

## Performance — the pure spec and the extracted C

The speed story has two parts, and they are measured separately because they are
different objects (`[D10]`): the **pure spec** (SMT-facing, `Seq`-carried) and the
**extracted C** (Pulse over `Pulse.Lib.Array`, `u32`-indexed, no allocation).

### The two objects, and why they are measured separately

`[D10]` already says the spec carrier and the runtime carrier are different
objects. Performance follows: a claim about the pure spec is a claim about what
SMT discharges, and a claim about the C is a claim about emitted code. No law in
this repository states anything about emitted code, so nothing here can be
_derived_ — only measured, or named as unmeasured.

### Where the C speed comes from

`Data.Codec.Pulse`'s leaf `fn`s carry byte-level separation-logic post-conditions,
so every byte the C writes is accounted for by a `pts_to` assertion, and those
post-conditions are proved to agree with the pure spec. That is the point of
`[D11]`: an 8-leaf closed dispatcher over `Pulse.Lib.Array.array U8.t` with `u32`
offsets is what makes "no allocation on the hot path" a structural property of the
shipped artifact rather than an intention. The dispatch surface is a tag
comparison, not a closure call, because Custard emits neither closures nor sum
types.

### What is _not_ yet measured

The criterion for this work is "correct in code and fast in C", and the honest
position is that **the C cost of the migration is not yet measured** — it is item
6 of the change's obligation ledger and part of `[W8]`. `varint`'s
canonicalisation adds one comparison on an already-loaded register (rejecting a
non-final zero group); that is an _estimate_ until the extracted C is inspected
and timed, and it is recorded as an estimate rather than a result.

Until that measurement exists, this document makes **no throughput claim**. A
number invented here would be precisely the defect the migration exists to
remove.

## Getting started

The build toolchain comes from the Nix flake:

```bash
nix develop                     # the dev shell (F* + Pulse + Z3)

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
shared/static library). The authoritative verification gate is `nix build
.#checked`; the LSP is a dev-loop aid, not a substitute.

The build is three layers:

| File | Responsibility | Works without flakes? |
|------|----------------|-----------------------|
| `flake.nix` | inputs/outputs + `devShell` | no (needs flakes) |
| `default.nix` | builds `checked` / `ocaml` / `native` / `fsharp` | yes (`nix-build` / `import`) |
| `Makefile` | the shell-script verify (module order) | yes (plain `fstar` on PATH) |

Toolchain: F\* `v2026.09.20+lsp`. `Data.Codec.Pulse` is the Pulse leaf (8 leaf
codecs + dispatch + roundtrip lemmas) that compiles to C11, OCaml, and F#.

**On the four targets.** `checked` is the verification gate and uses **no
`--codegen` at all**; `make check` likewise writes only `out/checked`. The
`native` (C) and `fsharp` derivations build directly from `checked` — neither
depends on `ocaml` or `ocaml-src`, which are independent packaging derivations. So
the OCaml target is a **by-product of verification**, not a step in the C path:
dropping it would remove a dune package and change nothing about the C artifact.
It is kept because it is the only _executable_ model of the pure spec — the C tier
covers 8 leaves (`[W6]`), so OCaml is how a composite codec such as
`product`/`sep_by1` can be run to see its actual bytes.

Test modules (verified, not extracted):

| Module | Role |
|--------|------|
| `Data.Codec.Test.Roundtrip` | Pure roundtrip and error-path property tests (121). |
| `Data.Codec.Test.Pulse` | Buffer-based roundtrip + error tests for the Pulse leaf (10). |
| `Data.Codec.Test.Integration` | Binds every test + lemma, enforcing coverage. |

See `CHANGELOG.md` for what has changed, and `LICENSE.md` for the terms
(**dual-licensed**: AGPL-3.0-or-later, or a commercial license from the author —
the commercial terms are at the top).
