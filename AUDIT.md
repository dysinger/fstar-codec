# AUDIT — where `codec` drifted from our intent

> **Status:** planning/audit artifact.  This document records the places the
> F\* `codec` library *drifted* from the design intent it cites: Rendel &
> Ostermann's *"Invertible Syntax Descriptions"* (Haskell Symposium 2010).
> It is the **companion to** the Lean port planning done in
> `../lean-codec/openspec/invertible-binary/` — that port is paper-grounded,
> **not** a transcription of this library.
>
> This document is deliberately **critical**, not descriptive: it enumerates
> the divergences so a future reader (or a future extraction/refactor) does not
> mistake `codec`'s specific shape for the paper's abstraction.  It is **not**
> a bug list; most of the "drift" below is a *reasonable* design for a binary
> serialization library that the paper never set out to build.

---

## 1. The lineage claim is looser than the design

`README.md` says the library "descends from *invertible syntax descriptions*"
and cites Rendel & Ostermann.  That is a **lineage claim**, not a design
claim.  The paper's central objects are:

- **partial isomorphisms** `Iso α β = (α → Maybe β) × (β → Maybe α)` with an
  inverse invariant, composed as a category (§3.1, §5.1), and
- **syntax descriptions** = a single program interpreted polysemantically as
  parser or printer, via `$` / `*` / `|` / `empty` / `pure` / `token` (§3.4),
  with a **denotational relation semantics** (§4.3): a description *is* a
  graph between abstract values and concrete strings.

`codec` has **none** of these.  It has a single fat record (`codec a`) with
eight fields, a per-value well-formedness guard, a suffix "rest condition",
error-position/consumed-byte bound proofs, and a roundtrip lemma field — a
*binary serialization* design, not the paper's *relation of partial
isomorphisms* design.

**Drift:** the README's "proves — not merely tests — that encoding and
decoding are inverses" is true of `codec`, but the *mechanism* is Z3/SMT
discharging a `dec (enc v ++ r) == Inr (v, |enc v|)` lemma on a record — the
precise thing the paper avoids.  In the paper, invertibility is **structural**
(partial isomorphisms invert by construction, no solver) and the roundtrip is
a **relation statement** (§4.3), not a solver-verified lemma on a record.

---

## 2. Concrete syntax: `String`/`Char` → `Seq byte` (binary)

The paper's concrete syntax is `String` (a list of `Char`), and the whole
treatment — whitespace (`skipSpace`/`optSpace`/`sepSpace` §6.3), operator
precedence via nested `exp i` (§6.4) — is *human-readable-syntax* flavored.

`codec` replaces this with `byte_seq = Seq.seq byte`, and every combinator is
byte-oriented: `byte_val`, `uint8`, `word16/32 be/le`, `varint`, `bytes`.

**Drift:** this is **not wrong** — the stated *intent* for downstream work is
binary (image files, Protobuf-style variable-length framing), which the paper
never addresses.  But it is a *re-targeting* of the paper, not a port.  The
paper's `token : Char` (§3.4) and `element`/`subset` partial isomorphisms over
characters have no byte-level analogue that `codec` merely instantiates; they
were replaced wholesale by an endianness/varint *binary* vocabulary.

### 2a. Text/Unicode is handled only as lossy ASCII truncation — not Unicode

The only "text" primitive is `text : string → codec unit` (`Types.fst:1089`),
built on `string_to_bytes` (`Types.fst:160-168`):

```fstar
let string_to_bytes (s: string) =
  seq_of_list (map (fun c -> U8.uint_to_t (Char.int_of_char c % 256))   -- % 256
                   (String.list_of_string s))
```

`text`'s `wfcv` is `string_is_ascii s` (`Types.fst:176`, "every code point
`< 128`"), so *well-formed* text is ASCII-only, and the docstring is explicit:
"code points > 255 are truncated via `% 256`.  This library does not handle
Unicode."

**Drift:** this is **not** a Unicode codec.  There is no UTF-8 (or any
multi-byte) encoding, no code-point-vs-code-unit distinction, and no validity
handling — a code point `≥ 256` (emoji, CJK, most non-Latin-1 accented text)
is silently *corrupted* to `code point mod 256` unless the ASCII guard rejects
the string first.  The paper's `String = [Char]` is genuine Unicode code points
(more correct than this); the `char_to_byte` helper in `Data.Codec.fst:184` is
a *rejection* mechanism (map non-ASCII to `0xFF` so it never matches an ASCII
predicate), not Unicode support.  A faithful port that claims to be "more
correct than the paper" must therefore add a real `utf8 : Iso (List Char)
(List UInt8)` with proved overlong/surrogate/invalid rejection — nothing in
`codec` provides it.

---

## 3. One type → two directions became eight record fields

The paper's "one description, two directions" is a **single value** whose
`parse`/`print` are *two interpretations of one interface* (§3.4, §4.1–4.2).
The *relation* is primary; parse and print are both "find a member of the
relation."

`codec` inverts this: the *functions* are primary (`enc` and `dec` are two
separate total functions), and the *relation* is reconstructed only implicitly
through a `roundtrip` lemma, a `wfcv` guard, a `wfcv_prop`, and a `rest_cond`
framing condition.

**Drift:** the paper's relation and its partiality (`α → Maybe β`, `Maybe
String`) are flattened into `enc : a → byte_seq` and `dec : byte_seq →
decode_result a` (total, error-coded).  Partiality — the paper's mechanism for
`empty`/`pure x`/`subset p` to *reject* out-of-domain values — is instead
pushed out into `wfcv : a → bool` (a runtime guard) plus `wfcv_prop : a →
prop` (a proof-only mirror).  The "is it printable/parseable" question and the
"is it in-domain" question are the **same** thing in the paper (one `Maybe`),
but are **twice-encoded** in `codec`.

---

## 4. The roundtrip is borne by Z3, not by structure

The paper's invertibility is *free*: compose partial isomorphisms whose laws
compose (`Category`, `×`), and every derived combinator (`many`, `chainl1`,
`foldl`/`iterate`) is invertible by construction.

`codec`'s roundtrip is a **per-combinator lemma** (`roundtrip : (v: a) -> (r:
byte_seq) -> Lemma ...`) that Z3 must discharge.  This required:

- `SMTPat` triggers (`bytes_decode`, `lemma_seq_cons_append`) to get the solver
  to fire,
- `--z3rlimit` tuning (40/80/120/400/800) per proof region,
- a hand-maintained div/mod "head-normal form" lemma block
  (`lemma_varint_*_arithmetic`) to feed the solver,
- and at least two documented **non-terminating Z3 episodes** (the Pulse `varint`
  roundtrip; a comment-layout-sensitive hang near the varint lemmas).

**Drift:** all of that machinery is *a consequence of choosing a monolithic
record whose behavior the typechecker cannot unfold*, then asking a solver to
reconstruct the invertibility the paper gets structurally.  Each lemma is
correct (the library is 0-admit), but the *architecture* of proving is the
inverse of the paper's.  None of `SMTPat`/`rlimit`/`fuel`/head-normal-shaping
is a semantic requirement of invertible parsing; it is a property of the
solver-based proof tactic.

---

## 5. Verification burden correlated with *comment layout* is a smell

`AGENTS.md` records that collapsing `(** *)` one-line comments near
`nbytes_of_varint` / `lemma_varint_*byte_arithmetic` **correlated with** the
varint roundtrip becoming a non-terminating Z3 spin (mechanism unproven,
reverted to restore green).

**Drift:** this is not a *design* drift but a *maintenance* smell that signals
the proof is near the solver's decision boundary.  In a paper-faithful Lean
port, the analog would be a **structurally simpler** proof (list induction over
a byte model, `Nat.div_add_mod`/`Nat.mod_eq_of_lt`), where "does it re-verify
after I reflow a comment" is not a question that can arise.

---

## 6. The `wfcv`/`rest_cond`/`dec_*_bound` trio has no paper analogue

`codec`'s record carries three proof fields the paper never needs:

- `dec_err_bound : (s) → Lemma (Inl err ⇒ err.err_pos ≤ |s|)`,
- `dec_consumed_bound : (s) → Lemma (Inr (_, n) ⇒ n ≤ |s|)`,
- and the value-level `rest_cond` (what must hold of the bytes *after* the
  encoded value).

The paper has **no error positions**, **no consumed-byte accounting**, and **no
suffix framing condition** — because its concrete syntax is a whole `String`,
and a description's meaning (§4.3) is a whole-string relation with no notion of
"remaining input to be framed."

**Drift:** these are *binary serialization* concerns (offsets, truncation,
framing) that are genuinely useful for the targeted domain, but they are
**additions on top of the paper**, and they are what makes the `codec` record
so much heavier than the paper's thin `Iso`/`Syntax` abstractions.  A
paper-faithful port would treat error reporting and framing as *orthogonal
layers*, not record fields.

---

## 7. The Pulse/C layer is a third design under one name

`Data.Codec.Pulse` is a Pulse separation-logic layer (8 leaf codecs, C11
extraction via Custard) whose spec is *hand-inlined* and *not* the pure
`.enc`/`.dec` projections — hence its own separate, fragile varint roundtrip.

**Drift:** this is a **byte-buffer / C-extraction** concern, entirely absent
from the paper.  Its presence under the `codec` name blurs the line between
"the abstract invertible-syntax idea" and "a specific C library for byte
buffers."  For the Lean port, this whole layer is out of scope; `ByteArray` +
`UInt8/16/32/64` + native extraction is the paper-faithful, speed-first
alternative.

---

## Summary of drift

| # | Paper (intent) | `codec` (actual) | Character |
|---|---|---|---|
| 1 | partial isomorphisms + relation semantics | fat `codec a` record + per-combinator lemma | design replaced |
| 2 | `String`/`Char` concrete syntax | `Seq byte` + endianness/varint leaves | re-targeted (binary) |
| 3 | one relation, two interpretations, `Maybe` partiality | `enc`/`dec` total + `wfcv`/`wfcv_prop` | partiality pushed to guards |
| 4 | invertibility **structural** (compose laws) | invertibility **solver-discharged** (Z3) | proof architecture inverted |
| 5 | — | comment-layout-sensitive verification | maintenance smell |
| 6 | — | `dec_err_bound`/`dec_consumed_bound`/`rest_cond` | binary-serialization additions |
| 7 | — | Pulse separation-logic C layer | third design, C extraction |

**Bottom line:** `codec` is a *good binary serialization library* that cites
the paper for motivation.  It is **not** an implementation of the paper.  The
Lean port (`../lean-codec/openspec/invertible-binary/`) deliberately starts
over from the **paper**, treats binary leaves as *instances* of a clean
`Iso`/`Syntax`/`Rel` core (not record fields), keeps `print` partial, and gets
speed from `ByteArray` + extraction — not from a solver or a C layer.
