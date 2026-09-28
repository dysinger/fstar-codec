(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Test.Pulse — buffer-based roundtrip + error-path tests for the Pulse leaf.

Ten Pulse `fn` tests that call the [Data.Codec.Pulse] roundtrip lemmas and the
encode/decode dispatch through an [Pulse.Lib.Array.array], exercising the
byte-buffer code path.  Each test brackets a single `A.alloc`/`A.free` pair
(the Pulse analogue of the old Low* `alloca` + `push_frame`/`pop_frame`) and
forces the expected result constructor by pattern match.

Kept in a dedicated `#lang-pulse` module because Pulse reserves the `label`
keyword, which the pure test modules ([Data.Codec.Test.Roundtrip],
[Data.Codec.Test.Integration]) use freely as a codec combinator and record
field.

@header Data.Codec.Test.Pulse
*)
module Data.Codec.Test.Pulse
#lang-pulse

open Pulse
open Pulse.Lib.Reference
open Data.Codec.Pulse
open FStar.UInt8
open FStar.UInt32

module A = Pulse.Lib.Array
module US = FStar.SizeT

(** Pulse roundtrip: token encode→decode through an A.array buffer. *)
fn test_stack_token_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 2sz;
  let (_, result) = lemma_pulse_roundtrip_token 0x42ul buf 0ul 2ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: uint8 encode→decode through an A.array buffer. *)
fn test_stack_uint8_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 2sz;
  let (_, result) = lemma_pulse_roundtrip_uint8 42ul buf 0ul 2ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: byte_val encode→decode through an A.array buffer. *)
fn test_stack_byteval_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 2sz;
  let (_, result) = lemma_pulse_roundtrip_byteval 0x5Buy buf 0ul 2ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: word16be encode→decode through an A.array buffer. *)
fn test_stack_word16be_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 3sz;
  let (_, result) = lemma_pulse_roundtrip_word16be 0xABCDul buf 0ul 3ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: word32be encode→decode through an A.array buffer. *)
fn test_stack_word32be_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 5sz;
  let (_, result) = lemma_pulse_roundtrip_word32be 0xDEADBEEFul buf 0ul 5ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: word16le encode→decode through an A.array buffer. *)
fn test_stack_word16le_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 3sz;
  let (_, result) = lemma_pulse_roundtrip_word16le 0xCDABul buf 0ul 3ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: word32le encode→decode through an A.array buffer. *)
fn test_stack_word32le_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 5sz;
  let (_, result) = lemma_pulse_roundtrip_word32le 0xEFBEADDEul buf 0ul 5ul;
  let Data.Codec.Pulse.DR_Inr _ = result;
  A.free buf
}

(** Pulse roundtrip: varint encode→decode through an A.array buffer.
    Tests the 5-range varint encoding (1..5 bytes) at concrete boundaries. *)
fn test_stack_varint_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 6sz;
  let (_, result_0) = lemma_pulse_roundtrip_varint 0ul buf 0ul 6ul;
  let Data.Codec.Pulse.DR_Inr _ = result_0;
  let (_, result_128) = lemma_pulse_roundtrip_varint 128ul buf 0ul 6ul;
  let Data.Codec.Pulse.DR_Inr _ = result_128;
  let (_, result_16384) = lemma_pulse_roundtrip_varint 16384ul buf 0ul 6ul;
  let Data.Codec.Pulse.DR_Inr _ = result_16384;
  let (_, result_2097152) = lemma_pulse_roundtrip_varint 2097152ul buf 0ul 6ul;
  let Data.Codec.Pulse.DR_Inr _ = result_2097152;
  let (_, result_268435456) = lemma_pulse_roundtrip_varint 268435456ul buf 0ul 6ul;
  let Data.Codec.Pulse.DR_Inr _ = result_268435456;
  A.free buf
}

(** Pulse error test: decode_varint overflow detection.
    Writes a 5-byte varint whose 5th byte exceeds the 15-value cap, then
    asserts decode_varint produces a DR_Inl (EC_Overflow). *)
fn test_stack_varint_overflow ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 5sz;
  let j0 = US.uint32_to_sizet 0ul;
  buf.(j0) <- 0xFFuy;
  let j1 = US.uint32_to_sizet 1ul;
  buf.(j1) <- 0xFFuy;
  let j2 = US.uint32_to_sizet 2ul;
  buf.(j2) <- 0xFFuy;
  let j3 = US.uint32_to_sizet 3ul;
  buf.(j3) <- 0xFFuy;
  let j4 = US.uint32_to_sizet 4ul;
  buf.(j4) <- 0x10uy;
  let result = decode_varint buf 0ul 5ul;
  let Data.Codec.Pulse.DR_Inl _ = result;
  A.free buf
}

(** Pulse roundtrip through the dispatch table:
    encode_bytes CT_Varint → decode_bytes CT_Varint. *)
fn test_stack_varint_dispatch_roundtrip ()
    requires emp
    returns u: unit
    ensures emp
{
  let buf = A.alloc 0uy 6sz;
  let v = 300ul;
  let written = encode_bytes CT_Varint v buf 0ul;
  let result = decode_bytes CT_Varint buf 0ul written;
  let Data.Codec.Pulse.DR_Inr r = result;
  A.free buf
}
