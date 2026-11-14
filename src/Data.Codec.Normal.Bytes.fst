(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Normal.Bytes — the concrete ASCII normalisers, and their laws.

[Data.Codec.Normal] holds the shape and is generic (no domain leaf).  This module
is where the concrete ASCII predicates live, per the module scope rule: anything
that names a character or an ASCII predicate belongs outside the core.

Two normalisers, covering the two cases the user asked for — *optional characters
that carry no semantics*:

- [strip_spaces] — drop every space byte.  This is the **length-shrinking**
  case: three blanks and one blank share a class, and both share it with zero
  blanks.  The Lean port's [Normal.lean] declines this for a length-indexed
  carrier; [Seq byte] is length-agnostic, so it is expressible here.
- [fold_upper] — fold ASCII upper case to lower case.  This is the
  **length-preserving** case (RFC 4648 §8 permits a decoder to accept both
  cases for Base16, since the case of a hex digit carries no information).

Both are proved idempotent, which is the only law [normalizer] requires.  Neither
invents a byte: [strip_spaces] of the empty input is empty, so **absence stays
absence** and remains a strict rejection.

@header Data.Codec.Normal.Bytes
*)

module Data.Codec.Normal.Bytes

module Seq = FStar.Seq
module U8 = FStar.UInt8
module Normal = Data.Codec.Normal

let byte = FStar.UInt8.t
let byte_seq = Seq.seq byte

(** The space byte.  Named, so the predicate reads as prose. *)
let space_byte : byte = 32uy

(** An ASCII upper-case byte: [65 .. 90] ([A .. Z]). *)
let is_upper (b: byte) : Tot bool = U8.v b >= 65 && U8.v b <= 90

(** The case-folding offset: [65 .. 90] maps to [97 .. 122]. *)
let case_offset : nat = 32

(** The space predicate: the character carries no semantics. *)
let is_space (b: byte) : Tot bool = (b = space_byte)

(** [strip_spaces s] drops every space byte from [s].

    Defined by a length test with the recursive call on a slice tail, so the
    [decreases] is on [|s|] and each step is one byte shorter.  The result is
    **no longer than its input** — the refinement is what keeps the shrink honest.
*)
let rec strip_spaces (s: byte_seq)
  : Tot (out: byte_seq { Seq.length out <= Seq.length s })
  (decreases Seq.length s)
  = if Seq.length s = 0 then Seq.empty
    else
      let head = Seq.index s 0 in
      let tail = Seq.slice s 1 (Seq.length s) in
      let rest = strip_spaces tail in
      if is_space head then rest
      else Seq.cons head rest

(**
[strip_spaces]'s unfolding on a non-empty input, as an equation.

SMT proves an unfolded equation but will not *derive* it from the call (research
`F48`), so it is stated.  Without this the idempotence proof cannot start.
*)
let lemma_strip_spaces_unfold (s: byte_seq)
  : Lemma (requires Seq.length s > 0)
          (ensures (strip_spaces s ==
                    (if is_space (Seq.index s 0)
                     then strip_spaces (Seq.slice s 1 (Seq.length s))
                     else Seq.cons (Seq.index s 0)
                                  (strip_spaces (Seq.slice s 1 (Seq.length s))))))
  = ()

(** [strip_spaces] of a space-headed sequence equals [strip_spaces] of its tail. *)
let lemma_strip_spaces_space_head (head: byte) (tail: byte_seq)
  : Lemma (requires is_space head = true)
          (ensures (strip_spaces (Seq.cons head tail) == strip_spaces tail))
  = let s = Seq.cons head tail in
    lemma_strip_spaces_unfold s;
    Seq.lemma_index_app1 (Seq.create 1 head) tail 0;
    Seq.lemma_index_create 1 head 0;
    Seq.lemma_eq_intro (Seq.slice s 1 (Seq.length s)) tail

(** [strip_spaces] of a head that is not a space keeps the head, then strips. *)
let lemma_strip_spaces_other_head (head: byte) (tail: byte_seq)
  : Lemma (requires is_space head = false)
          (ensures (strip_spaces (Seq.cons head tail) ==
                    Seq.cons head (strip_spaces tail)))
  = let s = Seq.cons head tail in
    lemma_strip_spaces_unfold s;
    Seq.lemma_index_app1 (Seq.create 1 head) tail 0;
    Seq.lemma_index_create 1 head 0;
    Seq.lemma_eq_intro (Seq.slice s 1 (Seq.length s)) tail

(**
**The law [strip_spaces] owes: it is idempotent.**

Proved by induction on [|s|], with the two [cons] steps above so that no [if] in
the conclusion has to hold both faces at once (a known chaining failure).
*)
let rec lemma_strip_spaces_idempotent (s: byte_seq)
  : Lemma (strip_spaces (strip_spaces s) == strip_spaces s)
          (decreases Seq.length s)
  = if Seq.length s = 0 then ()
    else
      let head = Seq.index s 0 in
      let tail = Seq.slice s 1 (Seq.length s) in
      lemma_strip_spaces_unfold s;
      lemma_strip_spaces_idempotent tail;
      if is_space head
      then lemma_strip_spaces_space_head head (strip_spaces tail)
      else lemma_strip_spaces_other_head head (strip_spaces (strip_spaces tail))

(** The shrinking normalizer, ready to pass to [Normal.fill]. *)
let strip_spaces_normalizer : Normal.normalizer strip_spaces =
  { normalizer_idem = lemma_strip_spaces_idempotent }

(**
**Padding collapses.**  Three blanks, one blank, and no blanks are one class — so
[strip_spaces] is a genuine quotient, not a per-input function.

This is the concrete claim: a decoder that accepts optional padding is the strict
codec applied to [strip_spaces]'s output.
*)
let lemma_padding_collapses ()
  : Lemma ((Normal.fill strip_spaces_normalizer (Seq.create 3 space_byte)).Normal.normal_bytes
           == (Normal.fill strip_spaces_normalizer (Seq.create 1 space_byte)).Normal.normal_bytes /\
           (Normal.fill strip_spaces_normalizer (Seq.create 3 space_byte)).Normal.normal_bytes
           == (Normal.fill strip_spaces_normalizer Seq.empty).Normal.normal_bytes /\
           strip_spaces (Seq.create 3 space_byte) == Seq.empty)
  = ()

(**
**Absence is not a spelling.**  Stripping the empty input yields empty: no
[strip_spaces] call invents a byte, so the empty input stays out of every value's
class and is rejected by the strict codec.  This is the boundary the paper's
equivalence-class reading must not be stretched across.
*)
let lemma_absence_stays_empty ()
  : Lemma ((Normal.fill strip_spaces_normalizer Seq.empty).Normal.normal_bytes == Seq.empty)
  = ()

(** [fold_upper] folds an ASCII upper-case byte to lower case; others are fixed. *)
let fold_upper (b: byte) : Tot byte =
  if is_upper b then U8.uint_to_t (U8.v b + case_offset) else b

(**
**The law [fold_upper] owes: it is idempotent.**

The length-preserving case.  The proof is by cases: a folded byte is in
[97 .. 122], which is outside [65 .. 90], so folding again fixes it.
*)
let lemma_fold_upper_idempotent (b: byte)
  : Lemma (fold_upper (fold_upper b) == fold_upper b)
  = if is_upper b then () else ()

(** [fold_all_upper s] folds every byte of [s] to lower case.  Length-preserving:
    the output has the same length as the input. *)
let fold_all_upper (s: byte_seq)
  : Tot (out: byte_seq { Seq.length out == Seq.length s })
  = let len = Seq.length s in
    Seq.init len (fun (i: nat{i < len}) -> fold_upper (Seq.index s i))

(** The pointwise step at a bounded index: folding an already-folded byte fixes it. *)
let lemma_fold_all_upper_point (s: byte_seq) (i: nat{i < Seq.length s})
  : Lemma (Seq.index (fold_all_upper (fold_all_upper s)) i
           == Seq.index (fold_all_upper s) i)
  = lemma_fold_upper_idempotent (Seq.index s i)

(** Idempotence lifts pointwise, because [Seq.init] is extensional on the index. *)
let lemma_fold_all_upper_idempotent (s: byte_seq)
  : Lemma (fold_all_upper (fold_all_upper s) == fold_all_upper s)
  = Seq.lemma_eq_intro
      (fold_all_upper (fold_all_upper s))
      (fold_all_upper s)

(** The length-preserving normalizer. *)
let fold_upper_normalizer : Normal.normalizer fold_all_upper =
  { normalizer_idem = lemma_fold_all_upper_idempotent }

(**
**Case collapse.**  [0x41] ([A]) and [0x61] ([a]) are one class: the case of a
hex digit carries no information, so RFC 4648 §8's permission is expressed as a
quotient rather than as a second decoder.
*)
(** [fold_all_upper] on a single-byte sequence is the pointwise fold. *)
let lemma_fold_all_upper_index (s: byte_seq) (i: nat{i < Seq.length s})
  : Lemma (Seq.index (fold_all_upper s) i == fold_upper (Seq.index s i))
  = ()

let lemma_fold_all_upper_singleton (b: byte)
  : Lemma (fold_all_upper (Seq.create 1 b) == Seq.create 1 (fold_upper b))
  = let s = Seq.create 1 b in
    Seq.lemma_create_len 1 b;
    assert (Seq.length s = 1);
    lemma_fold_all_upper_index s 0;
    Seq.lemma_eq_intro (fold_all_upper s) (Seq.create 1 (fold_upper b))

(** [fill]'s content is [norm]'s output, so the class comparison is about bytes. *)
let lemma_case_collapses ()
  : Lemma ((Normal.fill fold_upper_normalizer (Seq.create 1 65uy)).Normal.normal_bytes ==
           (Normal.fill fold_upper_normalizer (Seq.create 1 97uy)).Normal.normal_bytes)
  = let upper : byte = 65uy in
    let lower : byte = 97uy in
    lemma_fold_all_upper_singleton upper;
    lemma_fold_all_upper_singleton lower;
    assert (is_upper upper = true);
    assert (is_upper lower = false);
    assert (fold_upper upper == U8.uint_to_t (U8.v upper + case_offset));
    assert (U8.v upper + case_offset = 97);
    assert (U8.uint_to_t (U8.v upper + case_offset) == lower);
    assert (fold_upper lower == lower)

(** And it is **length-preserving**: the folded output has the input's length. *)
let lemma_fold_upper_length (b: byte)
  : Lemma (Seq.length (fold_all_upper (Seq.create 1 b)) == Seq.length (Seq.create 1 b))
  = ()
