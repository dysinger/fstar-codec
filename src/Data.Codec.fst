(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec — Derived combinators, operator aliases, and character predicates.

Re-exports all 19 base combinators from [Data.Codec.Types] via [include].

@header Data.Codec
*)
module Data.Codec

open FStar.Seq

include Data.Codec.Types

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
(** [digits_to_int_alias] — alias for [digits_to_int]. *)
let digits_to_int_alias = digits_to_int

(** Character predicates *)

(** [is_upper] — ASCII uppercase [A–Z]. *)
let is_upper (b: byte) : bool =
  let v = U8.v b in 0x41 <= v && v <= 0x5A

(** [is_lower] — ASCII lowercase [a–z]. *)
let is_lower (b: byte) : bool =
  let v = U8.v b in 0x61 <= v && v <= 0x7A

(** [is_alpha] — ASCII alphabetic ([is_upper] ∨ [is_lower]). *)
let is_alpha (b: byte) : bool = is_upper b || is_lower b

(** [is_alphanum] — ASCII alphanumeric ([is_alpha] ∨ [is_digit]). *)
let is_alphanum (b: byte) : bool = is_alpha b || is_digit b

(** [is_space_or_tab] — space or horizontal tab. *)
let is_space_or_tab (b: byte) : bool =
  let v = U8.v b in v = 0x20 || v = 0x09

(** [is_whitespace] — space, tab, CR, or LF. *)
let is_whitespace (b: byte) : bool =
  let v = U8.v b in v = 0x20 || v = 0x09 || v = 0x0D || v = 0x0A

(** [is_printable] — visible ASCII ([0x20, 0x7E]). *)
let is_printable (b: byte) : bool =
  let v = U8.v b in 0x20 <= v && v <= 0x7E

(** [char_to_byte] — truncate a [char] to its low 8 bits. *)
let char_to_byte (c: FStar.Char.char) : byte =
  U8.uint_to_t (FStar.Char.int_of_char c % 256)

(** [char_is_digit] — is the character a digit? *)
let char_is_digit (c: FStar.Char.char) : bool =
  is_digit (char_to_byte c)

(** [char_is_upper] — is the character ASCII uppercase? *)
let char_is_upper (c: FStar.Char.char) : bool =
  is_upper (char_to_byte c)

(** [char_is_lower] — is the character ASCII lowercase? *)
let char_is_lower (c: FStar.Char.char) : bool =
  is_lower (char_to_byte c)

(** [char_is_alpha] — is the character ASCII alphabetic? *)
let char_is_alpha (c: FStar.Char.char) : bool =
  is_alpha (char_to_byte c)

(** [char_is_alphanum] — is the character ASCII alphanumeric? *)
let char_is_alphanum (c: FStar.Char.char) : bool =
  is_alphanum (char_to_byte c)

(** [char_is_space_or_tab] — is the character space or tab? *)
let char_is_space_or_tab (c: FStar.Char.char) : bool =
  is_space_or_tab (char_to_byte c)

(** [char_is_whitespace] — is the character whitespace? *)
let char_is_whitespace (c: FStar.Char.char) : bool =
  is_whitespace (char_to_byte c)

(** [char_is_printable] — is the character printable ASCII? *)
let char_is_printable (c: FStar.Char.char) : bool =
  is_printable (char_to_byte c)

(** [digit_byte] — a codec for a single ASCII digit byte. *)
let digit_byte : codec byte = satisfy is_digit
