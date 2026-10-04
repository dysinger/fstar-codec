(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Pulse — C-extractable codec layer via Pulse + Custard.

Non-recursive leaf codecs (8 types) operating on [Pulse.Lib.Array.array].
Each encode/decode function has a byte-level post-condition expressed as
Pulse separation logic.

The pure codec spec lives in [Data.Codec.Types]; this module proves
correspondence with it.  Written for F* v2026.09.20 (Custard `--custard_backend C`).

@header Data.Codec.Pulse

@section Types
- [codec_t] — flat GADT: CT_Token, CT_ByteVal, CT_Uint8, CT_Word16BE,
  CT_Word32BE, CT_Word16LE, CT_Word32LE, CT_Varint
- [error_code_c] — C-compatible error codes
- [decode_result_c] — C-compatible decode result

@section Encode functions
Eight leaf encoders, each a Pulse `fn` with byte-level post-condition.
Dispatch via [encode_bytes].

@section Decode functions
Eight leaf decoders, each a Pulse `fn` with result correspondence.
Dispatch via [decode_bytes].
*)
module Data.Codec.Pulse
#lang-pulse

open Pulse
open Pulse.Lib.Reference
module A = Pulse.Lib.Array
module US = FStar.SizeT
module U8 = FStar.UInt8
module U16 = FStar.UInt16
module U32 = FStar.UInt32
module Seq = FStar.Seq
module Cast = FStar.Int.Cast

open FStar.Seq
open FStar.Int.Cast

open Data.Codec.Types

module DC = Data.Codec.Types


(* ── Types (carried over unchanged) ─────────────────────────────────── *)


(** Flat codec tag — 8 leaf types extractable to C.

    CT_Satisfy excluded: function-typed constructor breaks extraction.
    CT_Bytes, CT_Text excluded: use the pure-spec bridge. *)
type codec_t =
  | CT_Token      (** Any single byte *)
  | CT_ByteVal of U8.t  (** Specific b byte *)
  | CT_Uint8      (** Unsigned 8-bit integer *)
  | CT_Word16BE   (** Big-endian 16-bit integer *)
  | CT_Word32BE   (** Big-endian 32-bit integer *)
  | CT_Word16LE   (** Little-endian 16-bit integer *)
  | CT_Word32LE   (** Little-endian 32-bit integer *)
  | CT_Varint     (** Variable-length integer *)


(** C-compatible error codes. *)
type error_code_c =
  | EC_UnexpectedEndOfInput
  | EC_ExpectedByte of U8.t
  | EC_Overflow


(** C-compatible decode error. *)
type decode_error_c = { code: error_code_c; pos: U32.t }


(** C-compatible successful decode result. *)
type decode_result_ok = { n: U32.t; value: U32.t }


(** C-compatible decode result: either error or success.

    The [value] field is a single boxed [U32.t] even though the pure layer
    ([Data.Codec.Types.decode_result a]) is polymorphic in [a].  This is
    DELIBERATE: the Pulse/Custard leaf must realize a uniform value type in
    C, which has no sum types — every scalar leaf (byte, uint8, word16be/le,
    word32be/le, varint) decodes into the same [U32.t] slot, and [DR_Inl]/
    [DR_Inr] are the discriminated-union tags.  The [DR_] prefix on the
    constructors avoids collision with the stdlib [either]'s [Inl]/[Inr];
    0xFF byte values are carried by widening a [U8] to [U32] at the boundary
    (see [uint8_to_uint32]).  Do NOT refactor this to an [either]-based
    polymorphic sum — doing so breaks [.#fsharp]/[.#native] extraction. *)
type decode_result_c =
  | DR_Inl of decode_error_c
  | DR_Inr of decode_result_ok


(* ── Encode functions — each with full byte-level post-condition ─────── *)


(** Encode an expected byte value into a buffer. Returns 1ul.

    @param x The single byte to write.
    @param b The destination buffer (must hold at least 1 byte at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [1ul]).
    The byte written equals [(DC.byte_val x).enc ()]. *)
fn encode_byteval (x: U8.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 1 <= A.length b)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 1 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 1)
                `Seq.equal` (DC.byte_val x).enc ())) **
      pure (w == 1ul)
{
  let j = US.uint32_to_sizet i;
  A.pts_to_len b;
  b.(j) <- x;
  1ul
}


(** Encode a single byte token into a buffer at offset. Returns 1ul.

    @param v The value (must satisfy [U32.v v < 256], its low 8 bits are written).
    @param b The destination buffer (must hold at least 1 byte at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [1ul]).
    The byte written equals [DC.token.enc (uint32_to_uint8 v)]. *)
fn encode_token (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 1 <= A.length b /\ U32.v v < 256)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 1 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 1)
                `Seq.equal` DC.token.enc (uint32_to_uint8 v))) **
      pure (w == 1ul)
{
  let x = uint32_to_uint8 v;
  let j = US.uint32_to_sizet i;
  A.pts_to_len b;
  b.(j) <- x;
  1ul
}


(** Encode an unsigned 8-bit integer as a single byte.

    @param v The value to encode (must satisfy [U32.v v < 256]).
    @param b The destination buffer (must hold at least 1 byte at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [1ul]).
    The byte written equals [DC.uint8.enc (U32.v v)]. *)
fn encode_uint8 (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 1 <= A.length b /\ U32.v v < 256)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 1 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 1)
                `Seq.equal` DC.uint8.enc (U32.v v))) **
      pure (w == 1ul)
{
  let x = uint32_to_uint8 v;
  let j = US.uint32_to_sizet i;
  A.pts_to_len b;
  b.(j) <- x;
  1ul
}


(** Encode a big-endian 16-bit integer as two bytes (high then low).

    @param v The value to encode (must satisfy [U32.v v < 65536]).
    @param b The destination buffer (must hold at least 2 bytes at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [2ul]).
    The two bytes equal [DC.word16be.enc (U32.v v)]. *)
fn encode_word16be (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 2 <= A.length b /\ U32.v v < 65536 /\ U32.v i + 1 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 2 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 2)
                `Seq.equal` DC.word16be.enc (U32.v v))) **
      pure (w == 2ul)
{
  let hi = uint32_to_uint8 (U32.div v 256ul);
  let lo = uint32_to_uint8 (U32.rem v 256ul);
  let j = US.uint32_to_sizet i;
  let j1 = US.uint32_to_sizet (U32.add i 1ul);
  A.pts_to_len b;
  b.(j) <- hi;
  b.(j1) <- lo;
  2ul
}


(** Encode a little-endian 16-bit integer as two bytes (low then high).

    @param v The value to encode (must satisfy [U32.v v < 65536]).
    @param b The destination buffer (must hold at least 2 bytes at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [2ul]).
    The two bytes equal [DC.word16le.enc (U32.v v)]. *)
fn encode_word16le (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 2 <= A.length b /\ U32.v v < 65536 /\ U32.v i + 1 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 2 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 2)
                `Seq.equal` DC.word16le.enc (U32.v v))) **
      pure (w == 2ul)
{
  let lo = uint32_to_uint8 (U32.rem v 256ul);
  let hi = uint32_to_uint8 (U32.div v 256ul);
  let j = US.uint32_to_sizet i;
  let j1 = US.uint32_to_sizet (U32.add i 1ul);
  A.pts_to_len b;
  b.(j) <- lo;
  b.(j1) <- hi;
  2ul
}


(** Encode a big-endian 32-bit integer as four bytes (most significant first).

    @param v The value to encode.
    @param b The destination buffer (must hold at least 4 bytes at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [4ul]).
    The four bytes equal [DC.word32be.enc (U32.v v)]. *)
fn encode_word32be (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 4 <= A.length b /\ U32.v i + 3 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 4 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 4)
                `Seq.equal` DC.word32be.enc (U32.v v))) **
      pure (w == 4ul)
{
  let b0 = uint32_to_uint8 (U32.div v 16777216ul);
  let b1 = uint32_to_uint8 (U32.rem (U32.div v 65536ul) 256ul);
  let b2 = uint32_to_uint8 (U32.rem (U32.div v 256ul) 256ul);
  let b3 = uint32_to_uint8 (U32.rem v 256ul);
  let j = US.uint32_to_sizet i;
  let j1 = US.uint32_to_sizet (U32.add i 1ul);
  let j2 = US.uint32_to_sizet (U32.add i 2ul);
  let j3 = US.uint32_to_sizet (U32.add i 3ul);
  A.pts_to_len b;
  b.(j) <- b0;
  b.(j1) <- b1;
  b.(j2) <- b2;
  b.(j3) <- b3;
  4ul
}


(** Encode a little-endian 32-bit integer as four bytes (least significant first).

    @param v The value to encode.
    @param b The destination buffer (must hold at least 4 bytes at [i]).
    @param i The write offset.
    @returns The number of bytes written (always [4ul]).
    The four bytes equal [DC.word32le.enc (U32.v v)]. *)
fn encode_word32le (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 4 <= A.length b /\ U32.v i + 3 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 4 <= A.length b /\
              Seq.length s1 == A.length b /\
              Seq.slice s1 (U32.v i) (U32.v i + 4)
                `Seq.equal` DC.word32le.enc (U32.v v))) **
      pure (w == 4ul)
{
  let b0 = uint32_to_uint8 (U32.rem v 256ul);
  let b1 = uint32_to_uint8 (U32.rem (U32.div v 256ul) 256ul);
  let b2 = uint32_to_uint8 (U32.rem (U32.div v 65536ul) 256ul);
  let b3 = uint32_to_uint8 (U32.div v 16777216ul);
  let j = US.uint32_to_sizet i;
  let j1 = US.uint32_to_sizet (U32.add i 1ul);
  let j2 = US.uint32_to_sizet (U32.add i 2ul);
  let j3 = US.uint32_to_sizet (U32.add i 3ul);
  A.pts_to_len b;
  b.(j) <- b0;
  b.(j1) <- b1;
  b.(j2) <- b2;
  b.(j3) <- b3;
  4ul
}


(** varint_encode_pred: canonical predicate describing varint-encoded bytes. *)
(** Single source of truth (mirrors the dead leaf + Types.fst). *)
(* varint_encode_pred: spec-only — noextract so Custard does not root it.
   It is referenced only from erased ensures clauses. *)
noextract
let varint_encode_pred (n: nat) (s: Seq.seq U8.t) (i: nat) : prop =
  if i + nbytes_of_varint n <= Seq.length s then
    (if n < 128 then
      U8.v (Seq.index s i) == n
    else if n < 16384 then
      U8.v (Seq.index s i) == n % 128 + 128 /\
      U8.v (Seq.index s (i + 1)) == n / 128
    else if n < 2097152 then
      U8.v (Seq.index s i) == n % 128 + 128 /\
      U8.v (Seq.index s (i + 1)) == (n / 128) % 128 + 128 /\
      U8.v (Seq.index s (i + 2)) == n / 16384
    else if n < 268435456 then
      U8.v (Seq.index s i) == n % 128 + 128 /\
      U8.v (Seq.index s (i + 1)) == (n / 128) % 128 + 128 /\
      U8.v (Seq.index s (i + 2)) == (n / 16384) % 128 + 128 /\
      U8.v (Seq.index s (i + 3)) == n / 2097152
    else
      U8.v (Seq.index s i) == n % 128 + 128 /\
      U8.v (Seq.index s (i + 1)) == (n / 128) % 128 + 128 /\
      U8.v (Seq.index s (i + 2)) == (n / 16384) % 128 + 128 /\
      U8.v (Seq.index s (i + 3)) == (n / 2097152) % 128 + 128 /\
      U8.v (Seq.index s (i + 4)) == n / 268435456)
  else False


(** Encode a variable-length integer.  Conservative 5-byte precondition.

    @param v The value to encode.
    @param b The destination buffer (must hold at least 5 bytes at [i]).
    @param i The write offset.
    @returns The number of bytes written: [nbytes_of_varint (U32.v v)]
             (1..5, matching the pure [DC.varint] layout).
    The written bytes satisfy [varint_encode_pred (U32.v v)]. *)
fn encode_varint (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + 5 <= A.length b /\ U32.v i + 4 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (U32.v i + 5 <= A.length b /\
              Seq.length s1 == A.length b /\
              varint_encode_pred (U32.v v) s1 (U32.v i))) **
      pure (U32.v w == nbytes_of_varint (U32.v v))
{
  let n = v;
  if U32.lt n 128ul {
    let j = US.uint32_to_sizet i;
    let x = uint32_to_uint8 n;
    A.pts_to_len b;
    b.(j) <- x;
    1ul
  } else if U32.lt n 16384ul {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let x0 = uint32_to_uint8 (U32.rem n 128ul `U32.add` 128ul);
    let x1 = uint32_to_uint8 (U32.div n 128ul);
    A.pts_to_len b;
    b.(j0) <- x0;
    b.(j1) <- x1;
    2ul
  } else if U32.lt n 2097152ul {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let j2 = US.uint32_to_sizet (U32.add i 2ul);
    let x0 = uint32_to_uint8 (U32.rem n 128ul `U32.add` 128ul);
    let x1 = uint32_to_uint8 (U32.rem (U32.div n 128ul) 128ul `U32.add` 128ul);
    let x2 = uint32_to_uint8 (U32.div n 16384ul);
    A.pts_to_len b;
    b.(j0) <- x0;
    b.(j1) <- x1;
    b.(j2) <- x2;
    3ul
  } else if U32.lt n 268435456ul {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let j2 = US.uint32_to_sizet (U32.add i 2ul);
    let j3 = US.uint32_to_sizet (U32.add i 3ul);
    let x0 = uint32_to_uint8 (U32.rem n 128ul `U32.add` 128ul);
    let x1 = uint32_to_uint8 (U32.rem (U32.div n 128ul) 128ul `U32.add` 128ul);
    let x2 = uint32_to_uint8 (U32.rem (U32.div n 16384ul) 128ul `U32.add` 128ul);
    let x3 = uint32_to_uint8 (U32.div n 2097152ul);
    A.pts_to_len b;
    b.(j0) <- x0;
    b.(j1) <- x1;
    b.(j2) <- x2;
    b.(j3) <- x3;
    4ul
  } else {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let j2 = US.uint32_to_sizet (U32.add i 2ul);
    let j3 = US.uint32_to_sizet (U32.add i 3ul);
    let j4 = US.uint32_to_sizet (U32.add i 4ul);
    let x0 = uint32_to_uint8 (U32.rem n 128ul `U32.add` 128ul);
    let x1 = uint32_to_uint8 (U32.rem (U32.div n 128ul) 128ul `U32.add` 128ul);
    let x2 = uint32_to_uint8 (U32.rem (U32.div n 16384ul) 128ul `U32.add` 128ul);
    let x3 = uint32_to_uint8 (U32.rem (U32.div n 2097152ul) 128ul `U32.add` 128ul);
    let x4 = uint32_to_uint8 (U32.div n 268435456ul);
    A.pts_to_len b;
    b.(j0) <- x0;
    b.(j1) <- x1;
    b.(j2) <- x2;
    b.(j3) <- x3;
    b.(j4) <- x4;
    5ul
  }
}


(* ── Decode functions — each with result-level post-condition ───────── *)


(** Decode an expected byte value.

    @param x The single byte to match.
    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 1, value = 0) on match; else [DR_Inl] with
             [EC_ExpectedByte] (read byte differs) or [EC_UnexpectedEndOfInput].
    NOTE: the [EC_ExpectedByte] payload is the *actual* mismatching byte
    ([y] in the body), NOT the expected byte [x].  This diverges from the
    pure [DC.byte_val], whose [ExpectedByte] payload is the *expected* byte
    [b].  C consumers must read [EC_ExpectedByte] as "the byte actually
    present".  (Roundtrip lemmas only match [DR_Inl]/[DR_Inr], never the
    payload, so this asymmetry is unobservable to them.)
    Value matches [(DC.byte_val x).dec]. *)
fn decode_byteval (x: U8.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + U32.v n < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, (DC.byte_val x).dec input_slice with
        | DR_Inr rr, Inr ((), _) -> rr.n == 1ul /\ rr.value == 0ul
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lt i (U32.add i n) {
    let j = US.uint32_to_sizet i;
    let y = b.(j);
    if U8.eq y x {
      DR_Inr ({ n = 1ul; value = 0ul })
    } else {
      DR_Inl ({ code = EC_ExpectedByte y; pos = i })
    }
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode a single-byte token.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 1, value = byte) or [DR_Inl] [EC_UnexpectedEndOfInput].
    Value matches [DC.token.dec]. *)
fn decode_token (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + U32.v n < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.token.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 1ul /\ U32.v rr.value == U8.v dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lt i (U32.add i n) {
    let j = US.uint32_to_sizet i;
    let x = b.(j);
    DR_Inr ({ n = 1ul; value = uint8_to_uint32 x })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode an unsigned 8-bit integer from a single byte.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 1, value = byte) or [DR_Inl] on insufficent input.
    Value matches [DC.uint8.dec]. *)
fn decode_uint8 (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + U32.v n < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.uint8.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 1ul /\ U32.v rr.value == dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lt i (U32.add i n) {
    let j = US.uint32_to_sizet i;
    let x = b.(j);
    DR_Inr ({ n = 1ul; value = uint8_to_uint32 x })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode a big-endian 16-bit integer from two bytes.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 2, value = reconstructed uint16) or [DR_Inl].
    Value matches [DC.word16be.dec]. *)
fn decode_word16be (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + 2 <= A.length b /\
            U32.v i + U32.v n < 4294967296 /\ U32.v i + 2 < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.word16be.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 2ul /\ U32.v rr.value == dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lte (U32.add i 2ul) (U32.add i n) {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let hi = b.(j0);
    let lo = b.(j1);
    let value = U32.add (U32.mul (uint8_to_uint32 hi) 256ul) (uint8_to_uint32 lo);
    DR_Inr ({ n = 2ul; value = value })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode a little-endian 16-bit integer from two bytes.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 2, value = reconstructed uint16) or [DR_Inl].
    Value matches [DC.word16le.dec]. *)
fn decode_word16le (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + 2 <= A.length b /\
            U32.v i + U32.v n < 4294967296 /\ U32.v i + 2 < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.word16le.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 2ul /\ U32.v rr.value == dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lte (U32.add i 2ul) (U32.add i n) {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let lo = b.(j0);
    let hi = b.(j1);
    let value = U32.add (uint8_to_uint32 lo) (U32.mul (uint8_to_uint32 hi) 256ul);
    DR_Inr ({ n = 2ul; value = value })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode a big-endian 32-bit integer from four bytes.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 4, value = reconstructed uint32) or [DR_Inl].
    Value matches [DC.word32be.dec]. *)
fn decode_word32be (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + 4 <= A.length b /\
            U32.v i + U32.v n < 4294967296 /\ U32.v i + 4 < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.word32be.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 4ul /\ U32.v rr.value == dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lte (U32.add i 4ul) (U32.add i n) {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let j2 = US.uint32_to_sizet (U32.add i 2ul);
    let j3 = US.uint32_to_sizet (U32.add i 3ul);
    let b0 = b.(j0);
    let b1 = b.(j1);
    let b2 = b.(j2);
    let b3 = b.(j3);
    let value = U32.add (U32.add (U32.add
      (U32.mul (uint8_to_uint32 b0) 16777216ul)
      (U32.mul (uint8_to_uint32 b1) 65536ul))
      (U32.mul (uint8_to_uint32 b2) 256ul))
      (uint8_to_uint32 b3);
    DR_Inr ({ n = 4ul; value = value })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** Decode a little-endian 32-bit integer from four bytes.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns [DR_Inr] (n = 4, value = reconstructed uint32) or [DR_Inl].
    Value matches [DC.word32le.dec]. *)
fn decode_word32le (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + 4 <= A.length b /\
            U32.v i + U32.v n < 4294967296 /\ U32.v i + 4 < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
        match r, DC.word32le.dec input_slice with
        | DR_Inr rr, Inr (dec_val, _) -> rr.n == 4ul /\ U32.v rr.value == dec_val
        | DR_Inl _, Inl _ -> True
        | _, _ -> False))
{
  A.pts_to_len b;
  if U32.lte (U32.add i 4ul) (U32.add i n) {
    let j0 = US.uint32_to_sizet i;
    let j1 = US.uint32_to_sizet (U32.add i 1ul);
    let j2 = US.uint32_to_sizet (U32.add i 2ul);
    let j3 = US.uint32_to_sizet (U32.add i 3ul);
    let b0 = b.(j0);
    let b1 = b.(j1);
    let b2 = b.(j2);
    let b3 = b.(j3);
    let value = U32.add (U32.add (U32.add
      (uint8_to_uint32 b0)
      (U32.mul (uint8_to_uint32 b1) 256ul))
      (U32.mul (uint8_to_uint32 b2) 65536ul))
      (U32.mul (uint8_to_uint32 b3) 16777216ul);
    DR_Inr ({ n = 4ul; value = value })
  } else {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  }
}


(** varint_decode_expected: pure spec for decode_varint.

    WARNING: hand-maintained duplicate of [decode_varint]'s body — the two
    MUST stay byte-identical (the [fn]'s postcondition [r ==
    varint_decode_expected i n s0] is the only safety net, and it is only as
    strong as this spec faithfully mirrors the impl).  See AGENTS.md / the
    reviewer-findings W2 follow-up on deriving one from the other.

    Range asymmetry (W1): the 5th byte is constrained to [% 128 <= 15], so
    the Pulse layer accepts exactly [0, 2^32) — whereas the pure [varint]
    combinator's wfcv admits [0, 2^35) and [nbytes_of_varint] only returns 6
    for n >= 2^35.  A 5-byte value whose 5th byte is 16..127 overflows U32 and
    is rejected with [EC_Overflow].  There is no 6-byte Pulse path and no
    [lemma_varint_enc_dec_6byte] — the U32-bounded Pulse encode/decode is the
    deliberate, narrower surface (typical protocols need 32-bit wire values
    only).

    spec-only — noextract so Custard skips it. *)
noextract
let varint_decode_expected (i: U32.t) (n: U32.t) (s: Seq.seq U8.t { U32.v i + U32.v n <= Seq.length s }) : decode_result_c =
  if U32.lt n 1ul then
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  else
    let b0 = Seq.index s (U32.v i) in
    let v0 = U32.uint_to_t (U8.v b0 % 128) in
    if U8.v b0 < 128 then
      DR_Inr ({ n = 1ul; value = v0 })
    else if U32.lt n 2ul then
      DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
    else
      let b1 = Seq.index s (U32.v i + 1) in
      let v1 = U32.add v0 (U32.mul (U32.uint_to_t (U8.v b1 % 128)) 128ul) in
      if U8.v b1 < 128 then
        DR_Inr ({ n = 2ul; value = v1 })
      else if U32.lt n 3ul then
        DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
      else
        let b2 = Seq.index s (U32.v i + 2) in
        let v2 = U32.add v1 (U32.mul (U32.uint_to_t (U8.v b2 % 128)) 16384ul) in
        if U8.v b2 < 128 then
          DR_Inr ({ n = 3ul; value = v2 })
        else if U32.lt n 4ul then
          DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
        else
          let b3 = Seq.index s (U32.v i + 3) in
          let v3 = U32.add v2 (U32.mul (U32.uint_to_t (U8.v b3 % 128)) 2097152ul) in
          if U8.v b3 < 128 then
            DR_Inr ({ n = 4ul; value = v3 })
          else if U32.lt n 5ul then
            DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
          else
            let b4 = Seq.index s (U32.v i + 4) in
            let b4_val = U8.v b4 % 128 in
            if b4_val > 15 then
              DR_Inl ({ code = EC_Overflow; pos = i })
            else
              let v4 = U32.add v3 (U32.mul (U32.uint_to_t b4_val) 268435456ul) in
              DR_Inr ({ n = 5ul; value = v4 })


(** Decode a variable-length integer.

    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns The decode result; exactly [varint_decode_expected i n s0]
             (the pure spec defined immediately above). *)
fn decode_varint (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (U32.v i + U32.v n <= A.length b /\ U32.v i + 5 < 4294967296 /\
            U32.v i + 4 < 4294967296)
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (A.length b == Seq.length s0 /\
            U32.v i + U32.v n <= A.length b /\
            r == varint_decode_expected i n s0)
{
  A.pts_to_len b;
  if U32.lt n 1ul {
    DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
  } else {
    let j0 = US.uint32_to_sizet i;
    let b0 = b.(j0);
    let v0 = U32.rem (uint8_to_uint32 b0) 128ul;
    if U8.lt b0 128uy {
      DR_Inr ({ n = 1ul; value = v0 })
    } else if U32.lt n 2ul {
      DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
    } else {
      let j1 = US.uint32_to_sizet (U32.add i 1ul);
      let b1 = b.(j1);
      let v1 = U32.add v0 (U32.mul (U32.rem (uint8_to_uint32 b1) 128ul) 128ul);
      if U8.lt b1 128uy {
        DR_Inr ({ n = 2ul; value = v1 })
      } else if U32.lt n 3ul {
        DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
      } else {
        let j2 = US.uint32_to_sizet (U32.add i 2ul);
        let b2 = b.(j2);
        let v2 = U32.add v1 (U32.mul (U32.rem (uint8_to_uint32 b2) 128ul) 16384ul);
        if U8.lt b2 128uy {
          DR_Inr ({ n = 3ul; value = v2 })
        } else if U32.lt n 4ul {
          DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
        } else {
          let j3 = US.uint32_to_sizet (U32.add i 3ul);
          let b3 = b.(j3);
          let v3 = U32.add v2 (U32.mul (U32.rem (uint8_to_uint32 b3) 128ul) 2097152ul);
          if U8.lt b3 128uy {
            DR_Inr ({ n = 4ul; value = v3 })
          } else if U32.lt n 5ul {
            DR_Inl ({ code = EC_UnexpectedEndOfInput; pos = i })
          } else {
            let j4 = US.uint32_to_sizet (U32.add i 4ul);
            let b4 = b.(j4);
            let b4_val = U32.rem (uint8_to_uint32 b4) 128ul;
            if U32.gt b4_val 15ul {
              DR_Inl ({ code = EC_Overflow; pos = i })
            } else {
              let v4 = U32.add v3 (U32.mul b4_val 268435456ul);
              DR_Inr ({ n = 5ul; value = v4 })
            }
          }
        }
      }
    }
  }
}


(* ── Dispatch functions — each with full per-constructor post-condition ─ *)


(** [encode_bytes]: dispatch on [codec_t] with a full per-constructor byte spec.

    @param c The codec tag selecting the encoder.
    @param v The value to encode.
    @param b The destination buffer.
    @param i The write offset.
    @returns The number of bytes written, matching the leaf encoder for [c].
    Precondition and byte post-condition are exact per constructor — see the
    [match c with ...] body. *)
fn encode_bytes (c: codec_t) (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        match c with
        | CT_Token | CT_Uint8 ->
            U32.v i + 1 <= A.length b /\ U32.v v < 256
        | CT_ByteVal _ ->
            U32.v i + 1 <= A.length b
        | CT_Word16BE | CT_Word16LE ->
            U32.v i + 2 <= A.length b /\ U32.v v < 65536 /\ U32.v i + 1 < 4294967296
        | CT_Word32BE | CT_Word32LE ->
            U32.v i + 4 <= A.length b /\ U32.v i + 3 < 4294967296
        | CT_Varint ->
            U32.v i + 5 <= A.length b /\ U32.v i + 4 < 4294967296)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (
          Seq.length s1 == A.length b /\
          (match c with
           | CT_Token | CT_Uint8 -> U32.v i + 1 <= A.length b
           | CT_ByteVal _ -> U32.v i + 1 <= A.length b
           | CT_Word16BE | CT_Word16LE -> U32.v i + 2 <= A.length b
           | CT_Word32BE | CT_Word32LE -> U32.v i + 4 <= A.length b
           | CT_Varint -> U32.v i + 5 <= A.length b) /\
          (match c with
           | CT_Token ->
               Seq.slice s1 (U32.v i) (U32.v i + 1)
                 `Seq.equal` DC.token.enc (uint32_to_uint8 v)
           | CT_Uint8 ->
               Seq.slice s1 (U32.v i) (U32.v i + 1)
                 `Seq.equal` DC.uint8.enc (U32.v v)
           | CT_ByteVal x ->
               Seq.slice s1 (U32.v i) (U32.v i + 1)
                 `Seq.equal` (DC.byte_val x).enc ()
           | CT_Word16BE ->
               Seq.slice s1 (U32.v i) (U32.v i + 2)
                 `Seq.equal` DC.word16be.enc (U32.v v)
           | CT_Word32BE ->
               Seq.slice s1 (U32.v i) (U32.v i + 4)
                 `Seq.equal` DC.word32be.enc (U32.v v)
           | CT_Word16LE ->
               Seq.slice s1 (U32.v i) (U32.v i + 2)
                 `Seq.equal` DC.word16le.enc (U32.v v)
           | CT_Word32LE ->
               Seq.slice s1 (U32.v i) (U32.v i + 4)
                 `Seq.equal` DC.word32le.enc (U32.v v)
           | CT_Varint ->
               varint_encode_pred (U32.v v) s1 (U32.v i)))) **
      pure (
        match c with
        | CT_Token | CT_Uint8 | CT_ByteVal _ -> w == 1ul
        | CT_Word16BE | CT_Word16LE -> w == 2ul
        | CT_Word32BE | CT_Word32LE -> w == 4ul
        | CT_Varint -> U32.v w == nbytes_of_varint (U32.v v))
{
  match c {
    CT_Token -> { encode_token v b i }
    CT_ByteVal x -> { encode_byteval x b i }
    CT_Uint8 -> { encode_uint8 v b i }
    CT_Word16BE -> { encode_word16be v b i }
    CT_Word32BE -> { encode_word32be v b i }
    CT_Word16LE -> { encode_word16le v b i }
    CT_Word32LE -> { encode_word32le v b i }
    CT_Varint -> { encode_varint v b i }
  }
}


(** [decode_bytes]: dispatch on [codec_t] with a full per-constructor result spec.

    @param c The codec tag selecting the decoder.
    @param b The source buffer.
    @param i The read offset.
    @param n The number of available bytes from [i].
    @returns The decode result matching the leaf decoder for [c]. *)
fn decode_bytes (c: codec_t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + U32.v n <= A.length b /\ U32.v i + U32.v n < 4294967296 /\
        (match c with
         | CT_Word16BE | CT_Word16LE -> U32.v i + 2 <= A.length b /\ U32.v i + 2 < 4294967296
         | CT_Word32BE | CT_Word32LE -> U32.v i + 4 <= A.length b /\ U32.v i + 4 < 4294967296
         | CT_Varint -> U32.v i + 5 <= A.length b /\ U32.v i + 5 < 4294967296
         | _ -> True))
    returns r: decode_result_c
    ensures
      A.pts_to b s0 **
      pure (
        A.length b == Seq.length s0 /\
        U32.v i + U32.v n <= A.length b /\
        (let input_slice = Seq.slice s0 (U32.v i) (U32.v i + U32.v n) in
         match c with
         | CT_Token ->
             (match r, DC.token.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 1ul /\ U32.v rr.value == U8.v dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_ByteVal x ->
             (match r, (DC.byte_val x).dec input_slice with
              | DR_Inr rr, Inr ((), _) -> rr.n == 1ul /\ rr.value == 0ul
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Uint8 ->
             (match r, DC.uint8.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 1ul /\ U32.v rr.value == dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Word16BE ->
             (match r, DC.word16be.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 2ul /\ U32.v rr.value == dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Word32BE ->
             (match r, DC.word32be.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 4ul /\ U32.v rr.value == dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Word16LE ->
             (match r, DC.word16le.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 2ul /\ U32.v rr.value == dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Word32LE ->
             (match r, DC.word32le.dec input_slice with
              | DR_Inr rr, Inr (dec_val, _) -> rr.n == 4ul /\ U32.v rr.value == dec_val
              | DR_Inl _, Inl _ -> True
              | _, _ -> False)
         | CT_Varint -> r == varint_decode_expected i n s0))
{
  match c {
    CT_Token -> { decode_token b i n }
    CT_ByteVal x -> { decode_byteval x b i n }
    CT_Uint8 -> { decode_uint8 b i n }
    CT_Word16BE -> { decode_word16be b i n }
    CT_Word32BE -> { decode_word32be b i n }
    CT_Word16LE -> { decode_word16le b i n }
    CT_Word32LE -> { decode_word32le b i n }
    CT_Varint -> { decode_varint b i n }
  }
}


(* ── Value-preserving roundtrip lemmas ─────────────────────────────── ─ *)


(** [lemma_pulse_roundtrip_byteval]: encode then decode an expected byte.

    @param x The expected byte.
    @param b The buffer.
    @param i The offset.
    @param n The available decode length.
    Proves [decode_byteval x b i (encode_byteval x b i) == DR_Inr {n; value = 0ul}]. *)
fn lemma_pulse_roundtrip_byteval (x: U8.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + 1 <= A.length b /\
        U32.v i + 1 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = 0ul }))
{
  let m = encode_byteval x b i;
  let r = decode_byteval x b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_token]: encode then decode preserves the value.

    @param v The value (must satisfy [U32.v v < 256]).
    @param b The buffer.
    @param i The offset.
    @param n The available decode length.
    Proves [decode_token b i (encode_token v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_token (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v v < 256 /\
        U32.v i + 1 <= A.length b /\
        U32.v i + 1 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_token v b i;
  let r = decode_token b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_uint8]: encode then decode a uint8 preserves the value.

    @param v The value (must satisfy [U32.v v < 256]).
    @param b The buffer.
    @param i The offset.
    @param n The available decode length.
    Proves [decode_uint8 b i (encode_uint8 v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_uint8 (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v v < 256 /\
        U32.v i + 1 <= A.length b /\
        U32.v i + 1 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_uint8 v b i;
  let r = decode_uint8 b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_word16be]: encode then decode a big-endian uint16 roundtrips.

    @param v The value (must satisfy [U32.v v < 65536]).
    Proves [decode_word16be b i (encode_word16be v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_word16be (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v v < 65536 /\
        U32.v i + 2 <= A.length b /\
        U32.v i + 2 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_word16be v b i;
  let r = decode_word16be b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_word16le]: encode then decode a little-endian uint16 roundtrips.

    @param v The value (must satisfy [U32.v v < 65536]).
    Proves [decode_word16le b i (encode_word16le v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_word16le (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v v < 65536 /\
        U32.v i + 2 <= A.length b /\
        U32.v i + 2 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_word16le v b i;
  let r = decode_word16le b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_word32be]: encode then decode a big-endian uint32 roundtrips.

    @param v The value.
    Proves [decode_word32be b i (encode_word32be v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_word32be (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + 4 <= A.length b /\
        U32.v i + 4 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_word32be v b i;
  let r = decode_word32be b i m;
  (m, r)
}


(** [lemma_pulse_roundtrip_word32le]: encode then decode a little-endian uint32 roundtrips.

    @param v The value.
    Proves [decode_word32le b i (encode_word32le v b i) == DR_Inr {n; value = v}]. *)
fn lemma_pulse_roundtrip_word32le (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + 4 <= A.length b /\
        U32.v i + 4 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_word32le v b i;
  let r = decode_word32le b i m;
  (m, r)
}


(** Structural lemma: varint_enc → varint_dec roundtrips.  SMTPat-triggered so
    SMT applies it whenever it sees [varint_decode_expected i (nbytes_of_varint v) s]
    — exactly the goal produced by composing [encode_varint] then [decode_varint].
    Lifts the per-length div/mod decomposition out of the hot query. *)
noextract
let lemma_varint_roundtrip_smtpat (v: U32.t) (s: Seq.seq U8.t) (i: U32.t)
  : Lemma
    (requires
      varint_encode_pred (U32.v v) s (U32.v i) /\
      U32.v i + nbytes_of_varint (U32.v v) <= Seq.length s)
    (ensures
      varint_decode_expected i (U32.uint_to_t (nbytes_of_varint (U32.v v))) s
      == DR_Inr ({ n = U32.uint_to_t (nbytes_of_varint (U32.v v)); value = v }))
    [SMTPat (varint_decode_expected i (U32.uint_to_t (nbytes_of_varint (U32.v v))) s)]
  =
  let n = U32.v v in
  if n < 128 then ()
  else if n < 16384 then DC.lemma_varint_2byte_arithmetic n
  else if n < 2097152 then DC.lemma_varint_3byte_arithmetic n
  else if n < 268435456 then DC.lemma_varint_4byte_arithmetic n
  else DC.lemma_varint_5byte_arithmetic n


(** [lemma_pulse_roundtrip_varint]: encode then decode a varint roundtrips.

    @param v The value.
    Proves [decode_varint b i (encode_varint v b i) == DR_Inr {n; value = v}].
    Relies on [lemma_varint_roundtrip_smtpat] (defined immediately above) to
    discharge the 5-way threshold decomposition. *)
fn lemma_pulse_roundtrip_varint (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + 5 <= A.length b /\
        U32.v i + 5 <= U32.v i + U32.v n /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + 5 < 4294967296 /\
        U32.v i + 4 < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (snd res == DR_Inr ({ n = fst res; value = v }))
{
  let m = encode_varint v b i;
  let r = decode_varint b i m;
  (m, r)
}


(** [lemma_pulse_encode_decode_match]: dispatch-level master roundtrip lemma.

    @param c The codec tag.
    @param v The value.
    @param b The buffer.
    @param i The offset.
    @param n The available decode length.
    Proves [decode_bytes]∘[encode_bytes] roundtrips for every constructor:
    value preserved (or [0] for [CT_ByteVal]). *)
fn lemma_pulse_encode_decode_match (c: codec_t) (v: U32.t) (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        (match c with
         | CT_ByteVal _ ->
             U32.v i + 1 <= A.length b /\
             U32.v i + 1 <= U32.v i + U32.v n
         | CT_Token | CT_Uint8 ->
             U32.v v < 256 /\
             U32.v i + 1 <= A.length b /\
             U32.v i + 1 <= U32.v i + U32.v n
         | CT_Word16BE | CT_Word16LE ->
             U32.v v < 65536 /\
             U32.v i + 2 <= A.length b /\
             U32.v i + 2 <= U32.v i + U32.v n
         | CT_Word32BE | CT_Word32LE ->
             U32.v i + 4 <= A.length b /\
             U32.v i + 4 <= U32.v i + U32.v n
         | CT_Varint ->
             U32.v i + 5 <= A.length b /\
             U32.v i + 5 <= U32.v i + U32.v n) /\
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns res: (U32.t & decode_result_c)
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1) **
      pure (
        match c with
        | CT_ByteVal _ -> snd res == DR_Inr ({ n = fst res; value = 0ul })
        | _ -> snd res == DR_Inr ({ n = fst res; value = v }))
{
  match c {
    CT_Token -> { lemma_pulse_roundtrip_token v b i n }
    CT_ByteVal x -> { lemma_pulse_roundtrip_byteval x b i n }
    CT_Uint8 -> { lemma_pulse_roundtrip_uint8 v b i n }
    CT_Word16BE -> { lemma_pulse_roundtrip_word16be v b i n }
    CT_Word32BE -> { lemma_pulse_roundtrip_word32be v b i n }
    CT_Word16LE -> { lemma_pulse_roundtrip_word16le v b i n }
    CT_Word32LE -> { lemma_pulse_roundtrip_word32le v b i n }
    CT_Varint -> { lemma_pulse_roundtrip_varint v b i n }
  }
}
