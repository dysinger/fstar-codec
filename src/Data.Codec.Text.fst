(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Text — ASCII text codecs and character predicates.

Holds the ASCII string codec ([text]), the byte-level character predicates
([is_upper] … [is_printable]), and the [char_is_*] character family,
relocated verbatim from [Data.Codec.Types] and [Data.Codec].  This module
depends only on the format-agnostic core ([Data.Codec.Types]).

Behaviour is unchanged by the move: [text] is still ASCII-only and its
[wfcv] still rejects non-ASCII strings via [string_is_ascii].  Fixing that
(AUDIT §2a) is deliberately out of scope for this change.

@header Data.Codec.Text
*)
module Data.Codec.Text

open FStar.Seq

module Seq = FStar.Seq
module U8 = FStar.UInt8

open Data.Codec.Types

(** ASCII string leaves *)



(** string_to_bytes *)
let string_to_bytes (s: string) : Tot byte_seq =


  (* ASCII-only: code points > 255 are truncated via % 256.
     This library does not handle Unicode. Use string_is_ascii to guard. *)
  seq_of_list (FStar.List.Tot.map (fun (c: FStar.Char.char) ->
    U8.uint_to_t (FStar.Char.int_of_char c % 256))
    (FStar.String.list_of_string s))


(** string_is_ascii: true iff every character in s has code point < 128.

    Use as wfcv guard for text combinators to prevent silent truncation. *)
let string_is_ascii (s: string) : Tot bool =
  FStar.List.Tot.for_all (fun (c: FStar.Char.char) ->
    FStar.Char.int_of_char c < 128
  ) (FStar.String.list_of_string s)


(** Combinator 5: text — a fixed ASCII string.

    @param s The expected string (ASCII only).
    Encodes as [string_to_bytes s].  Decodes exactly [n] bytes and
    compares with [string_to_bytes s].  Fails with [ExpectedEndOfInput]
    if input is too short, [ExpectedText] on mismatch.
    wfcv requires [string_is_ascii s]. *)
#push-options "--z3rlimit 40"
let text (s: string) : codec unit = {
  enc       = (fun () -> string_to_bytes s);
  dec       = (fun input ->
    let expected = string_to_bytes s in
    let n = Seq.length expected in
    if Seq.length input < n then
      Inl (mk_decode_error ExpectedEndOfInput (Seq.length input))
    else if Seq.eq (Seq.slice input 0 n) expected then
      Inr ((), n)
    else Inl (mk_decode_error ExpectedText 0));
  wfcv      = (fun _ -> string_is_ascii s);
  wfcv_prop = (fun _ -> True);
  rest_cond = (fun _ _ -> True);
  roundtrip = (fun v r ->
    let b = string_to_bytes s in
    Seq.lemma_len_append b r;
    lemma_slice_append_prefix b r;
    ());
  dec_err_bound = (fun s -> ());
  dec_consumed_bound = (fun s -> ());
}
#pop-options



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


(** [char_to_byte] — map an ASCII [char] to its byte; a non-ASCII [char]
    ([int_of_char c >= 128]) maps to [0xFF] (which no ASCII predicate below
    matches), so a non-ASCII char is never silently accepted as a digit/
    letter/etc.  (Previously the body was [int_of_char c % 256], which silently
    wrapped code points [>= 256] into ASCII and produced false positives in
    [char_is_digit]/[char_is_upper]/… — see [lemma_non_ascii_char_byte].) *)
let char_to_byte (c: FStar.Char.char) : byte =
  let i = FStar.Char.int_of_char c in
  if i < 128 then U8.uint_to_t i else 0xFFuy


(** [lemma_non_ascii_char_byte] — a non-ASCII char maps to [0xFF], never an
    ASCII predicate byte. *)
let lemma_non_ascii_char_byte (c: FStar.Char.char)
  : Lemma (requires FStar.Char.int_of_char c >= 128)
          (ensures char_to_byte c == 0xFFuy)
  = ()


(** [lemma_ascii_char_byte_exact] — an ASCII char maps exactly (identity, no
    truncation), so [char_is_*] are exact for ASCII. *)
let lemma_ascii_char_byte_exact (c: FStar.Char.char)
  : Lemma (requires FStar.Char.int_of_char c < 128)
          (ensures char_to_byte c == U8.uint_to_t (FStar.Char.int_of_char c))
  = ()


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
