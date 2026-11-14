(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Normal — the information-free-variation quotient, as a type.

The paper (Rendel & Ostermann, §3.1) reads the inverse law *"modulo
equivalence classes"*: "a partial isomorphism maps strings of blanks of
arbitrary length to a unit value but maps the unit value back to a string of
blanks of length one—that is, all strings of blanks of arbitrary length are in
the same equivalence class".  §6.3 supplies the machinery
([skipSpace]/[optSpace]/[sepSpace]).

[Data.Codec.Types] answers that by *capturing* a permitted run and re-emitting it
verbatim, because a constant encoder cannot satisfy the law ([D4]).  That answer
is correct but incomplete: the honest object is a bijection with the **quotient
of the concrete syntax by the information-free variation** — not a relaxed law.

This module names that quotient as a **type**.  Because the quotient lives in
the object, the strict law in [Data.Codec.Types] is untouched, and every
theorem about it still applies.

@section Why a type and not a relaxed law

A quotient in the *morphism* is the prose invariant that [S1] exists to abolish.
A quotient in the *object* is ordinary category theory.  [normal] is the
fixed-point subtype of an idempotent [norm]; [fill] is surjective onto it
([lemma_fill_surj]), so it is a bijective copy of [s/~], not merely a subset.

@section What this module does NOT do

- It is **not** a codec, a combinator, or an inverse of an encoder.  There is no
  [codec] record here.  [dec_normal] has no inverse over raw input: [norm] is
  many-to-one, which is exactly what makes the quotient exist.
- It does not appear on the C hot path, by construction: it is pure spec, and
  nothing in [Data.Codec.Pulse] refers to it.
- It does not give an unconditional law over **raw** input.  [W1] stays open.

@header Data.Codec.Normal
*)

module Data.Codec.Normal

module Seq = FStar.Seq

(** The byte string carrier, re-exported for readability. *)
let byte = FStar.UInt8.t

(** The concrete syntax: a byte sequence.  Length-agnostic, so a *shortening*
    normalizer is expressible — which a length-indexed carrier is not. *)
let byte_seq = Seq.seq byte

(**
A **normal form** under [norm]: a byte sequence that [norm] fixes.

The quotient [s/~] is the set of these, where [s ~ t] iff [norm s == norm t].
[lemma_fill_surj] shows [fill] reaches every one, so this is a bijective copy of
the quotient and not a proper subset.

The fixedness witness is a [squash] rather than a bare [prop] so that [fill] can
build it as [()] after consuming the idempotence lemma.
*)
noeq
type normal (norm: byte_seq -> Tot byte_seq) = {
  (** The bytes of this class's canonical representative. *)
  normal_bytes : byte_seq;
  (** The quotient witness: [norm] fixes these bytes. *)
  normal_fixed : squash (norm normal_bytes == normal_bytes);
}

(**
A normalizer, and the single law it owes: idempotence.

[norm] is a **parameter** of this structure, not a projection field, so
[normal norm] is definitionally the same type wherever it appears.  The law is
carried by the *structure*, not passed at each use: a per-call proof argument
would let behaviour depend on which witness a caller supplied.
*)
noeq
type normalizer (norm: byte_seq -> Tot byte_seq) = {
  (** [norm] fixes its own output, which is what makes the fixed points a quotient. *)
  normalizer_idem : (x: byte_seq) -> Lemma (norm (norm x) == norm x);
}

(**
[fill nz s] presents [s] as a normal form: the canonical representative of its
equivalence class.  Its witness **is** the idempotence law, so [fill] needs no
other hypothesis — this is why the layer is cheap.

Note the asymmetry, which is the content of the whole layer: [norm ∘ fill] is the
identity ([lemma_fill_fixed]), but [fill ∘ norm] is *not*, because [norm] forgets
which spelling it was given.
*)
let fill (#norm: byte_seq -> Tot byte_seq) (nz: normalizer norm) (s: byte_seq)
  : normal norm
  = let _ = nz.normalizer_idem s in
    { normal_bytes = norm s; normal_fixed = () }

(** [fill]'s content is exactly [norm] applied to the input. *)
let lemma_fill_fixed (#norm: byte_seq -> Tot byte_seq) (nz: normalizer norm)
                     (s: byte_seq)
  : Lemma ((fill nz s).normal_bytes == norm s)
  = ()

(**
**Faithfulness of the reification.**  Every normal form is the canonical
representative of its own class, so [normal norm] is a bijective copy of the
quotient — not a subset.

This is the lemma that separates a quotient from a fudge: without it, the
subtype could be a proper subset of the quotient and the layer would lose
classes.
*)
let lemma_fill_surj (#norm: byte_seq -> Tot byte_seq) (nz: normalizer norm)
                    (f: normal norm)
  : Lemma (fill nz f.normal_bytes == f)
  = ()

(**
Two spellings occupy the same quotient class **exactly when** they normalise
equally.  This is the usable form of "one class, many spellings".

It is also the boundary theorem.  A *redundant spelling of a present value*
(padding, an overlong integer) is quotiented here.  The **absence** of a value is
not a spelling: no total idempotent [norm] maps it into a value's class, so it
stays a rejection in the strict codec.
*)
let lemma_fill_inj (#norm: byte_seq -> Tot byte_seq) (nz: normalizer norm)
                   (s t: byte_seq)
  : Lemma ((fill nz s).normal_bytes == (fill nz t).normal_bytes <==>
           norm s == norm t)
  = ()

(**
The **normalising decoder**: [norm] composed *outside* a strict decoder.

Deliberately not a codec and not a combinator.  It has no inverse over raw
input: many spellings map to one class.  It accepts input the strict codec
rejects, which is the entire point, and that is why it must never be presented
as a [codec] value or reach the extracted C.
*)
let dec_normal (#a: Type) (#norm: byte_seq -> Tot byte_seq)
               (decode: byte_seq -> Tot (option (a & byte_seq)))
               (s: byte_seq)
  : Tot (option (a & byte_seq))
  = decode (norm s)

(**
**The wrapper's law, with its precondition.**  On an input that is already a
normal form, the normalising decoder agrees with the strict decoder.

Thin by design: it states that the layer is transparent on normal forms, which
is the reusable step for the per-codec obligation below.
*)
let lemma_dec_normal_of_fixed (#a: Type) (norm: byte_seq -> Tot byte_seq)
                              (nz: normalizer norm)
                              (decode: byte_seq -> Tot (option (a & byte_seq)))
                              (s: byte_seq)
  : Lemma (requires norm s == s)
          (ensures dec_normal #a #norm decode s == decode s)
  = ()

(**
**The obligation, and what it buys.**  If the encoder emits a normal form
([hfixed]) and the strict decoder recovers the value, the normalising decoder
recovers it too.

The hypothesis is **not free** and must be discharged **per codec**.  Without it
the statement is *false*: a stripping [norm] can delete the encoder's own byte,
so [dec (norm (enc v))] can fail on the encoder's output.  This is the one
obligation the layer adds, and it is per-codec — not per-combinator — so it does
not reintroduce a doubled combinator surface.
*)
let lemma_dec_normal_encode (#a: Type) (norm: byte_seq -> Tot byte_seq)
                            (nz: normalizer norm)
                            (decode: byte_seq -> Tot (option (a & byte_seq)))
                            (encode: a -> Tot byte_seq)
                            (v: a) (e: byte_seq)
  : Lemma (requires norm e == e /\ encode v == e /\ decode e == Some (v, Seq.empty))
          (ensures dec_normal #a #norm decode e == Some (v, Seq.empty))
  = ()
