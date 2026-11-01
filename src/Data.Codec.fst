(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec — Derived combinators, operator aliases, and character predicates.

Re-exports every [Data.Codec.Types] symbol (all 22 combinators, plus
[one_of]/[take_until] helpers and every lemma) via [include].

@header Data.Codec
*)
module Data.Codec

open FStar.Seq

include Data.Codec.Types
include Data.Codec.Text

(* [include] re-exports to downstream modules; [open] is also
   needed so this module's own body can name Text symbols. *)
open Data.Codec.Text

module U8 = FStar.UInt8


(** Derived Combinators *)


(** [choice] — first-success alternative over a single type [a]: encode with the
    first arm whose [wfcv] holds (prefixed by [0x00]/[0x01] disk tag via [sum]). *)
let choice (#a:Type) (c1 c2: codec a) : codec a =
  map_ (fun (v: either a a) -> match v with | Inl x -> Some x | Inr x -> Some x)
       (fun (x: a) ->
         if c1.wfcv x then Some (Inl x)
         else if c2.wfcv x then Some (Inr x)
         else None)
       (sum c1 c2)


(** [lemma_choice_c1_dominates] — when both arms accept [x], [choice] encodes
    with a leading [0x00] tag (the [Inl] arm). *)
let lemma_choice_c1_dominates (#a:Type) (c1 c2: codec a) (x: a) : Lemma
  (requires c1.wfcv x /\ c2.wfcv x)
  (ensures (choice c1 c2).enc x == Seq.cons 0x00uy (c1.enc x))
  = assert ((choice c1 c2).enc x == (sum c1 c2).enc (Inl x));
    assert ((sum c1 c2).enc (Inl x) == Seq.cons 0x00uy (c1.enc x));
    ()


(** [lemma_choice_c2_dominates] — when only [c2] accepts [x], [choice] encodes
    with a leading [0x01] tag (the [Inr] arm). *)
let lemma_choice_c2_dominates (#a:Type) (c1 c2: codec a) (x: a) : Lemma
  (requires not (c1.wfcv x) /\ c2.wfcv x)
  (ensures (choice c1 c2).enc x == Seq.cons 0x01uy (c2.enc x))
  = assert ((choice c1 c2).enc x == (sum c1 c2).enc (Inr x));
    assert ((sum c1 c2).enc (Inr x) == Seq.cons 0x01uy (c2.enc x));
    ()


(** [then_drop] — run [c1] then [c2], dropping [c1]'s [unit] value. *)
let then_drop (#a:Type) (c1: codec unit) (c2: codec a) : codec a =
  map_ (fun (_, v) -> Some v) (fun v -> Some ((), v)) (product c1 c2)


(** [drop_then] — run [c1] then [c2], dropping [c2]'s [unit] value. *)
let drop_then (#a:Type) (c1: codec a) (c2: codec unit) : codec a =
  map_ (fun (v, _) -> Some v) (fun v -> Some (v, ())) (product c1 c2)


(** Operator [*>] — sequencing that keeps the right result. *)
let ( *> ) (#a:Type) (c1: codec unit) (c2: codec a) : codec a = then_drop c1 c2


(** Operator [<*] — sequencing that keeps the left result. *)
let ( <* ) (#a:Type) (c1: codec a) (c2: codec unit) : codec a = drop_then c1 c2


(** Operator [<|>] — infix alias for [choice]. *)
let ( <|> ) (#a:Type) (c1 c2: codec a) : codec a = choice c1 c2


(** [between] — run [open_], [c], then [close], keeping only [c]'s value. *)
let between (#a:Type) (open_ close: codec unit) (c: codec a) : codec a =
  map_ (fun ((_, v), _) -> Some v)
       (fun v -> Some (((), v), ()))
       (product (product open_ c) close)


(** [optional] — decode [c] or [unit]; encode [Some]/[None] with a [sum] tag. *)
let optional (#a:Type) (c: codec a) : codec (option a) =
  map_ (fun (v: either a unit) -> match v with | Inl x -> Some (Some x) | Inr _ -> Some None)
       (fun (opt: option a) -> match opt with | Some x -> Some (Inl x) | None -> Some (Inr ()))
       (sum c (pure ()))


(** [take] — [count n token]: a fixed [n]-byte prefix as a [list byte]. *)
let take (n: nat) : codec (list byte) = count n token


(** Backward-compat aliases *)


(** [word16_be] — alias for [word16be]. *)
let word16_be = word16be


(** [word32_be] — alias for [word32be]. *)
let word32_be = word32be


(** [word16_le] — alias for [word16le]. *)
let word16_le = word16le


(** [word32_le] — alias for [word32le]. *)
let word32_le = word32le


(** [varint_codec] — alias for [varint]. *)
let varint_codec = varint


(** [map] — alias for [map_]. *)
let map (#a #b: Type) (f: a -> Tot (option b)) (g: b -> Tot (option a)) (c: codec a) : codec b = map_ f g c


(** [equiv_map] — alias for [map_]. *)
let equiv_map = map_


(** [digits_to_integer] — alias for [digits_to_int]. *)
let digits_to_integer = digits_to_int


(** [many0] — long-name alias for [satisfy_many0]. *)
let many0 (f: byte -> Tot bool) : codec (list byte) = satisfy_many0 f


(** [many1] — long-name alias for [satisfy_many1]. *)
let many1 (f: byte -> Tot bool) : codec (list byte) = satisfy_many1 f
