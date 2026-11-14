(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Test.Normal — unit tests for the quotient layer.

Every lemma in [Data.Codec.Normal] and [Data.Codec.Normal.Bytes] is *called*
here with concrete arguments, so a proof that is deleted, renamed, or weakened
fails this module rather than silently disappearing.  This is the anchor the
lemma-coverage discipline requires.

The tests are concrete on purpose: they show a reader what the quotient layer
actually does to real bytes, quoting the paper's own example (blanks).

@header Data.Codec.Test.Normal
*)

module Data.Codec.Test.Normal

module Seq = FStar.Seq
module Normal = Data.Codec.Normal
module Bytes = Data.Codec.Normal.Bytes

let byte = FStar.UInt8.t
let byte_seq = Seq.seq byte

(**
A tiny *value* codec and its normalising wrapper, end to end.  This is the shape
a consumer writes: a strict decode, an encoder that emits a normal form, and
[dec_normal] outside.  Kept to one field so the arithmetic reduces.
*)
let one_byte_decode (s: byte_seq) : Tot (option (byte & byte_seq)) =
  if Seq.length s >= 1
  then Some (Seq.index s 0, Seq.slice s 1 (Seq.length s))
  else None

(**
The per-codec obligation, discharged for this codec: the encoder emits a normal
form.  A one-byte encoding never contains a space, so stripping it is the
identity — which is exactly the fact [lemma_dec_normal_encode] requires.
*)
let lemma_one_byte_enc_is_normal (b: byte)
  : Lemma (requires Bytes.is_space b = false)
          (ensures Bytes.strip_spaces (Seq.create 1 b) == Seq.create 1 b)
  = ()

(** **End-to-end.**  Decoding through the whitespace-stripping layer recovers the
    value from padded input, where the strict decoder would read the padding. *)
let test_dec_normal_padded ()
  : Lemma (Normal.dec_normal #byte #Bytes.strip_spaces one_byte_decode
             (Seq.cons Bytes.space_byte (Seq.create 1 7uy))
           == one_byte_decode (Seq.create 1 7uy))
  = Normal.lemma_dec_normal_of_fixed Bytes.strip_spaces Bytes.strip_spaces_normalizer
      one_byte_decode (Seq.create 1 7uy)

(**
**The quotient is faithful.**  [lemma_fill_surj]: every normal form is the
canonical representative of its own class.
*)
let test_fill_surj (s: byte_seq)
  : Lemma (Normal.fill Bytes.strip_spaces_normalizer
             (Normal.fill Bytes.strip_spaces_normalizer s).Normal.normal_bytes
           == Normal.fill Bytes.strip_spaces_normalizer s)
  = Normal.lemma_fill_surj Bytes.strip_spaces_normalizer
      (Normal.fill Bytes.strip_spaces_normalizer s)

(** [lemma_fill_fixed]: filling yields exactly [norm]'s output. *)
let test_fill_fixed (s: byte_seq)
  : Lemma ((Normal.fill Bytes.strip_spaces_normalizer s).Normal.normal_bytes
           == Bytes.strip_spaces s)
  = Normal.lemma_fill_fixed Bytes.strip_spaces_normalizer s

(** [lemma_fill_inj]: two spellings share a class exactly when they strip alike. *)
let test_fill_inj (s t: byte_seq)
  : Lemma ((Normal.fill Bytes.strip_spaces_normalizer s).Normal.normal_bytes
           == (Normal.fill Bytes.strip_spaces_normalizer t).Normal.normal_bytes
           <==> Bytes.strip_spaces s == Bytes.strip_spaces t)
  = Normal.lemma_fill_inj Bytes.strip_spaces_normalizer s t

(** **Padding collapses** — the paper's §3.1 example, made concrete. *)
let test_padding_collapses
  : squash (Bytes.strip_spaces (Seq.create 3 Bytes.space_byte) == Seq.empty)
  = Bytes.lemma_padding_collapses ()

(** **Absence is not a spelling** — the empty input stays empty. *)
let test_absence_stays_empty
  : squash ((Normal.fill Bytes.strip_spaces_normalizer Seq.empty).Normal.normal_bytes
            == Seq.empty)
  = Bytes.lemma_absence_stays_empty ()

(** The stripping normaliser's idempotence, exercised on a concrete input. *)
let test_strip_idempotent (s: byte_seq)
  : Lemma (Bytes.strip_spaces (Bytes.strip_spaces s) == Bytes.strip_spaces s)
  = Bytes.lemma_strip_spaces_idempotent s

(** The unfolding equation is reachable, so the proof it powers is anchored. *)
let test_strip_unfold (s: byte_seq)
  : Lemma (requires Seq.length s > 0)
          (ensures (Bytes.strip_spaces s ==
                    (if Bytes.is_space (Seq.index s 0)
                     then Bytes.strip_spaces (Seq.slice s 1 (Seq.length s))
                     else Seq.cons (Seq.index s 0)
                                  (Bytes.strip_spaces (Seq.slice s 1 (Seq.length s))))))
  = Bytes.lemma_strip_spaces_unfold s

(** The two [cons] steps. *)
let test_strip_space_head (head: byte) (tail: byte_seq)
  : Lemma (requires Bytes.is_space head = true)
          (ensures Bytes.strip_spaces (Seq.cons head tail) == Bytes.strip_spaces tail)
  = Bytes.lemma_strip_spaces_space_head head tail

let test_strip_other_head (head: byte) (tail: byte_seq)
  : Lemma (requires Bytes.is_space head = false)
          (ensures Bytes.strip_spaces (Seq.cons head tail)
                   == Seq.cons head (Bytes.strip_spaces tail))
  = Bytes.lemma_strip_spaces_other_head head tail

(** **Case collapse** occupies one class: [A] and [a] are the same value. *)
let test_case_collapses
  : squash ((Normal.fill Bytes.fold_upper_normalizer (Seq.create 1 65uy)).Normal.normal_bytes
            == (Normal.fill Bytes.fold_upper_normalizer (Seq.create 1 97uy)).Normal.normal_bytes)
  = Bytes.lemma_case_collapses ()

(** Case folding is idempotent, at one byte and pointwise over a sequence. *)
let test_fold_upper_idempotent (b: byte)
  : Lemma (Bytes.fold_upper (Bytes.fold_upper b) == Bytes.fold_upper b)
  = Bytes.lemma_fold_upper_idempotent b

let test_fold_all_upper_idempotent (s: byte_seq)
  : Lemma (Bytes.fold_all_upper (Bytes.fold_all_upper s) == Bytes.fold_all_upper s)
  = Bytes.lemma_fold_all_upper_idempotent s

let test_fold_all_upper_index (s: byte_seq) (i: nat{i < Seq.length s})
  : Lemma (Seq.index (Bytes.fold_all_upper s) i
           == Bytes.fold_upper (Seq.index s i))
  = Bytes.lemma_fold_all_upper_index s i

let test_fold_all_upper_singleton (b: byte)
  : Lemma (Bytes.fold_all_upper (Seq.create 1 b) == Seq.create 1 (Bytes.fold_upper b))
  = Bytes.lemma_fold_all_upper_singleton b

let test_fold_all_upper_point (s: byte_seq) (i: nat{i < Seq.length s})
  : Lemma (Seq.index (Bytes.fold_all_upper (Bytes.fold_all_upper s)) i
           == Seq.index (Bytes.fold_all_upper s) i)
  = Bytes.lemma_fold_all_upper_point s i

(** It is **length-preserving**: the property that makes it the `Bytes n` case. *)
let test_fold_upper_length (b: byte)
  : Lemma (Seq.length (Bytes.fold_all_upper (Seq.create 1 b))
           == Seq.length (Seq.create 1 b))
  = Bytes.lemma_fold_upper_length b

(** The per-codec obligation for the wrapper, called with a concrete encoder. *)
let test_dec_normal_encode (b: byte)
  : Lemma (requires Bytes.is_space b = false)
          (ensures Normal.dec_normal #byte #Bytes.strip_spaces one_byte_decode
                     (Seq.create 1 b)
                   == Some (b, Seq.empty))
  = lemma_one_byte_enc_is_normal b;
    Normal.lemma_dec_normal_encode Bytes.strip_spaces Bytes.strip_spaces_normalizer
      one_byte_decode (fun (x: byte) -> Seq.create 1 x) b (Seq.create 1 b)
