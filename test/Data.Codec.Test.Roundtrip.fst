(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Test.Roundtrip — Concrete roundtrip and error-path tests.

120 concrete tests with ZERO admits.  Each test calls encode, decode,
and asserts the expected result.  Uses both pure combinators and Stack-based
buffer I/O for the Pulse leaf codecs.

@header Data.Codec.Test.Roundtrip

@section Coverage
- Boundary values for varint (every threshold: 0, 127, 128, 16383, 16384,
  2097151, 2097152, 268435455, 268435456, max)
- Boundary values for word16 (0, 255, 256, 65535)
- Boundary values for word32 (0, max)
- All 19 combinators: roundtrip + error paths
- Derived combinators: choice, then_drop, drop_then, between, optional, take
- Stack-based roundtrip for all 8 Pulse leaf types + dispatch
- Character predicates (byte + char, positive + negative)
- Varint overflow and truncation at every byte boundary
- Label error propagation

Separate from [Data.Codec.Test.Integration] which uses [--admit_smt_queries]
for coverage anchors.
*)
module Data.Codec.Test.Roundtrip

open Data.Codec
open Data.Codec.Types
open Data.Codec.Pulse
open FStar.Seq
open FStar.UInt8
open FStar.UInt32
open FStar.HyperStack
open FStar.HyperStack.ST
open LowStar.Buffer

module U8 = FStar.UInt8
module U32 = FStar.UInt32
module LB = LowStar.Buffer
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST

(** Pure roundtrip tests *)

/// Test that encoding then decoding returns the original value.
/// Uses pure combinators (no Stack) for fast SMT checking.

#push-options "--z3rlimit 40"

let test_token_roundtrip () : Lemma
  (ensures token.dec (token.enc 0x42uy `Seq.append` Seq.empty) == Inr (0x42uy, 1))
  = lemma_create_len 1 0x42uy;
    token.roundtrip 0x42uy Seq.empty

let test_uint8_boundary_0 () : Lemma
  (ensures uint8.dec (uint8.enc 0 `Seq.append` Seq.empty) == Inr (0, 1))
  = lemma_create_len 1 (U8.uint_to_t (nat_of_int (0 % 256)));
    uint8.roundtrip 0 Seq.empty

let test_uint8_boundary_255 () : Lemma
  (ensures uint8.dec (uint8.enc 255 `Seq.append` Seq.empty) == Inr (255, 1))
  = lemma_create_len 1 (U8.uint_to_t (nat_of_int (255 % 256)));
    uint8.roundtrip 255 Seq.empty

let test_word16_boundary_0 () : Lemma
  (ensures word16be.dec (word16be.enc 0 `Seq.append` Seq.empty) == Inr (0, 2))
  = word16be.roundtrip 0 Seq.empty

let test_word16_boundary_255 () : Lemma
  (ensures word16be.dec (word16be.enc 255 `Seq.append` Seq.empty) == Inr (255, 2))
  = word16be.roundtrip 255 Seq.empty

let test_word16_boundary_256 () : Lemma
  (ensures word16be.dec (word16be.enc 256 `Seq.append` Seq.empty) == Inr (256, 2))
  = word16be.roundtrip 256 Seq.empty

let test_word16_boundary_65535 () : Lemma
  (ensures word16be.dec (word16be.enc 65535 `Seq.append` Seq.empty) == Inr (65535, 2))
  = word16be.roundtrip 65535 Seq.empty

let test_word32_boundary_0 () : Lemma
  (ensures word32be.dec (word32be.enc 0 `Seq.append` Seq.empty) == Inr (0, 4))
  = word32be.roundtrip 0 Seq.empty

let test_word32_boundary_max () : Lemma
  (ensures word32be.dec (word32be.enc 4294967295 `Seq.append` Seq.empty) == Inr (4294967295, 4))
  = word32be.roundtrip 4294967295 Seq.empty

(** Varint boundary tests *)

let test_varint_boundary_0 () : Lemma
  (ensures varint.dec (varint.enc 0 `Seq.append` Seq.empty) == Inr (0, 1))
  = varint.roundtrip 0 Seq.empty

let test_varint_boundary_127 () : Lemma
  (ensures varint.dec (varint.enc 127 `Seq.append` Seq.empty) == Inr (127, 1))
  = varint.roundtrip 127 Seq.empty

let test_varint_boundary_128 () : Lemma
  (ensures varint.dec (varint.enc 128 `Seq.append` Seq.empty) == Inr (128, 2))
  = varint.roundtrip 128 Seq.empty

let test_varint_boundary_16383 () : Lemma
  (ensures varint.dec (varint.enc 16383 `Seq.append` Seq.empty) == Inr (16383, 2))
  = varint.roundtrip 16383 Seq.empty

let test_varint_boundary_16384 () : Lemma
  (ensures varint.dec (varint.enc 16384 `Seq.append` Seq.empty) == Inr (16384, 3))
  = varint.roundtrip 16384 Seq.empty

let test_varint_boundary_2097151 () : Lemma
  (ensures varint.dec (varint.enc 2097151 `Seq.append` Seq.empty) == Inr (2097151, 3))
  = varint.roundtrip 2097151 Seq.empty

let test_varint_boundary_2097152 () : Lemma
  (ensures varint.dec (varint.enc 2097152 `Seq.append` Seq.empty) == Inr (2097152, 4))
  = varint.roundtrip 2097152 Seq.empty

let test_varint_boundary_268435455 () : Lemma
  (ensures varint.dec (varint.enc 268435455 `Seq.append` Seq.empty) == Inr (268435455, 4))
  = varint.roundtrip 268435455 Seq.empty

let test_varint_boundary_268435456 () : Lemma
  (ensures varint.dec (varint.enc 268435456 `Seq.append` Seq.empty) == Inr (268435456, 5))
  = varint.roundtrip 268435456 Seq.empty

let test_varint_boundary_max () : Lemma
  (ensures varint.dec (varint.enc 4294967295 `Seq.append` Seq.empty) == Inr (4294967295, 5))
  = varint.roundtrip 4294967295 Seq.empty

(** Error tests: decode truncated/empty input *)

let test_decode_empty_input () : Lemma
  (ensures token.dec Seq.empty == Inl (mk_decode_error UnexpectedEndOfInput 0))
  = ()

let test_decode_truncated_word16 () : Lemma
  (ensures word16be.dec (Seq.create 1 0x00uy) == Inl (mk_decode_error UnexpectedEndOfInput 1))
  = ()

let test_decode_truncated_word32 () : Lemma
  (ensures word32be.dec (Seq.create 2 0x00uy) == Inl (mk_decode_error UnexpectedEndOfInput 2))
  = ()

let test_decode_varint_error_truncated () : Lemma
  (ensures (match varint.dec (Seq.create 0 0x00uy) with
            | Inl err -> err.err_code == UnexpectedEndOfInput
            | _ -> False))
  = ()

(** Choice determinism test *)

let test_choice_c1_dominates () : Lemma
  (ensures (choice token (satisfy (fun _ -> true))).enc 0x42uy
        == Seq.cons 0x00uy (token.enc 0x42uy))
  = lemma_choice_c1_dominates token (satisfy (fun _ -> true)) 0x42uy

(** Product roundtrip test *)

let test_product_roundtrip () : Lemma
  (ensures (product token uint8).dec
    ((product token uint8).enc (0x42uy, 7) `Seq.append` Seq.empty)
    == Inr ((0x42uy, 7), 2))
  = token.roundtrip 0x42uy (uint8.enc 7 `Seq.append` Seq.empty);
    Seq.append_assoc (token.enc 0x42uy) (uint8.enc 7) Seq.empty;
    lemma_slice_after_prefix (token.enc 0x42uy) (uint8.enc 7 `Seq.append` Seq.empty);
    uint8.roundtrip 7 Seq.empty;
    ()

(** Sum roundtrip test *)

let test_sum_roundtrip_inl () : Lemma
  (ensures (sum token uint8).dec
    ((sum token uint8).enc (Inl 0x42uy) `Seq.append` Seq.empty)
    == Inr (Inl 0x42uy, 2))
  = lemma_seq_cons_append 0x00uy (token.enc 0x42uy) Seq.empty;
    token.roundtrip 0x42uy Seq.empty;
    lemma_slice_cons_spec 0x00uy (token.enc 0x42uy `Seq.append` Seq.empty);
    ()

(** Bytes roundtrip test *)

let test_bytes_roundtrip () : Lemma
  (ensures (bytes [0x00uy; 0x01uy; 0x02uy]).dec
    ((bytes [0x00uy; 0x01uy; 0x02uy]).enc () `Seq.append` Seq.empty)
    == Inr ((), 3))
  = (bytes [0x00uy; 0x01uy; 0x02uy]).roundtrip () Seq.empty

(** Text roundtrip test *)

#push-options "--z3rlimit 40"
let test_text_roundtrip () : Lemma
  (ensures (text "Hello").dec
    ((text "Hello").enc () `Seq.append` Seq.empty)
    == Inr ((), 5))
  = // text.roundtrip requires string_is_ascii + wfcv_prop.  Prove both
    // explicitly for "Hello" via assert_norm.
    assert_norm (string_is_ascii "Hello" = true);
    assert_norm (string_to_bytes "Hello" = seq_of_list [
      0x48uy; 0x65uy; 0x6Cuy; 0x6Cuy; 0x6Fuy]);
    (text "Hello").roundtrip () Seq.empty
#pop-options

(** Digits_to_int roundtrip test *)

let test_digits_to_int_roundtrip () : Lemma
  (ensures (digits_to_int 4 (fun n -> n < 2000)).dec
    ((digits_to_int 4 (fun n -> n < 2000)).enc 1234 `Seq.append` Seq.empty)
    == Inr (1234, 4))
  = let c = digits_to_int 4 (fun n -> n < 2000) in
    lemma_acc_digits_encode_helper 1234;
    lemma_digits_encode_all_digits_helper 1234;
    c.roundtrip 1234 Seq.empty

(** Count roundtrip test *)

let test_count_roundtrip () : Lemma
  (ensures (Data.Codec.Types.count 3 token).dec
    ((Data.Codec.Types.count 3 token).enc [0x01uy; 0x02uy; 0x03uy] `Seq.append` Seq.empty)
    == Inr ([0x01uy; 0x02uy; 0x03uy], 3))
  = let c = Data.Codec.Types.count 3 token in
    c.roundtrip [0x01uy; 0x02uy; 0x03uy] Seq.empty

(** Map_ roundtrip test *)

let test_map_roundtrip () : Lemma
  (ensures (map_ (fun b -> Some (U8.v b))
                 (fun i -> if i < 256 then Some (U8.uint_to_t i) else None)
                 token).dec
    ((map_ (fun b -> Some (U8.v b))
           (fun i -> if i < 256 then Some (U8.uint_to_t i) else None)
           token).enc 42 `Seq.append` Seq.empty)
    == Inr (42, 1))
  = let m = map_ (fun b -> Some (U8.v b))
                 (fun i -> if i < 256 then Some (U8.uint_to_t i) else None)
                 token in
    m.roundtrip 42 Seq.empty

(** Optional roundtrip tests *)

let test_optional_some_roundtrip () : Lemma
  (ensures (optional uint8).dec
    ((optional uint8).enc (Some 42) `Seq.append` Seq.empty)
    == Inr (Some 42, 2))
  = (optional uint8).roundtrip (Some 42) Seq.empty

let test_optional_none_roundtrip () : Lemma
  (ensures (optional uint8).dec
    ((optional uint8).enc None `Seq.append` Seq.empty)
    == Inr (None, 1))
  = (optional uint8).roundtrip None Seq.empty

(** Between roundtrip test *)

let test_between_roundtrip () : Lemma
  (ensures (between (byte_val 0x5Buy) (byte_val 0x5Duy) uint8).dec
    ((between (byte_val 0x5Buy) (byte_val 0x5Duy) uint8).enc 42 `Seq.append` Seq.empty)
    == Inr (42, 3))
  = (between (byte_val 0x5Buy) (byte_val 0x5Duy) uint8).roundtrip 42 Seq.empty

(** Error tests *)

let test_byteval_error_wrong_byte () : Lemma
  (ensures (byte_val 0x42uy).dec (Seq.create 1 0xFFuy) ==
    Inl (mk_decode_error (ExpectedByte 0x42uy) 0))
  = ()

let test_satisfy_error_fails_predicate () : Lemma
  (ensures (satisfy (fun b -> U8.v b = 0x42)).dec (Seq.create 1 0xFFuy) ==
    Inl (mk_decode_error ExpectedPredicate 0))
  = ()

let test_expected_sum_tag_error () : Lemma
  (ensures (sum token token).dec (Seq.create 1 0x02uy) ==
    Inl (mk_decode_error ExpectedSumTag 0))
  = ()

#push-options "--z3rlimit 40"
let test_expected_text_error () : Lemma
  (ensures (text "ABC").dec (string_to_bytes "ABD") ==
    Inl (mk_decode_error ExpectedText 0))
  = (* Normalize string_to_bytes → concrete seq_of_list, then
       assert_norm Seq.index on concrete lists so SMT sees 0x43uy <> 0x44uy
       at position 2.  This provides the Seq.eq inequality needed for the
       text.dec branch to resolve to ExpectedText. *)
    let expected = string_to_bytes "ABC" in
    let input = string_to_bytes "ABD" in
    assert_norm (expected == seq_of_list [0x41uy; 0x42uy; 0x43uy]);
    assert_norm (input == seq_of_list [0x41uy; 0x42uy; 0x44uy]);
    assert_norm (Seq.length (seq_of_list [0x41uy; 0x42uy; 0x43uy]) == 3);
    assert_norm (Seq.length (seq_of_list [0x41uy; 0x42uy; 0x44uy]) == 3);
    assert_norm (Seq.slice (seq_of_list [0x41uy; 0x42uy; 0x44uy]) 0 3
                 == seq_of_list [0x41uy; 0x42uy; 0x44uy]);
    assert_norm (Seq.index (seq_of_list [0x41uy; 0x42uy; 0x43uy]) 2 == 0x43uy);
    assert_norm (Seq.index (seq_of_list [0x41uy; 0x42uy; 0x44uy]) 2 == 0x44uy);
    assert (0x43uy <> 0x44uy);
    ()
#pop-options

let test_bytes_partial_match_error () : Lemma
  (ensures (bytes [0x00uy; 0x01uy]).dec (seq_of_list [0x00uy; 0xFFuy]) ==
    Inl (mk_decode_error (ExpectedByte 0x01uy) 1))
  = ()

/// The pure varint decoder accepts 5-byte encodings with b4 > 15,
/// producing values >= b4*128^4 = 16*268435456 = 4294967296.
/// With all continuation bytes maxed (0xFF each), value = 4563402751.
/// The Pulse decoder (Data.Codec.Pulse.decode_varint) rejects b4 > 15
/// via EC_Overflow — tested separately in test_varint_low_overflow.
#push-options "--z3rlimit 80"
let test_varint_5byte_oversized () : Lemma
  (ensures (match varint.dec (seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy; 0x10uy]) with
    | Inr (v, _) -> v == 4563402751
    | _ -> False))
  = lemma_nbytes_of_varint_correct 4563402751;
    lemma_varint_enc_dec_5byte 4563402751 Seq.empty;
    ()
#pop-options

/// Pulse overflow test: varint_decode_expected (the pure spec of decode_varint)
/// returns EC_Overflow for 5-byte input with b4 > 15.  Since decode_varint's
/// ensures clause equates its result to varint_decode_expected, this lemma
/// validates the Pulse overflow path without requiring Stack buffer allocation.
///
/// The 5th byte is 0x10uy: U8.v 0x10uy % 128 = 16 > 15, triggering EC_Overflow.
/// Explicit assert_norm proves this structurally rather than via SMT alone.
let test_varint_low_overflow () : Lemma
  (ensures Data.Codec.Pulse.varint_decode_expected
    (seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy; 0x10uy])
    0ul 5ul
    == Data.Codec.Pulse.DR_Inl ({code=Data.Codec.Pulse.EC_Overflow; pos=0ul}))
  = assert_norm (0x10 % 128 = 16);
    assert (16 > 15);
    ()

(** Pure combinator error path tests *)

/// decode_uint8 on empty input: verify UnexpectedEndOfInput.
let test_decode_uint8_empty () : Lemma
  (ensures uint8.dec Seq.empty == Inl (mk_decode_error UnexpectedEndOfInput 0))
  = ()

/// decode_byteval on empty input: verify UnexpectedEndOfInput.
let test_decode_byteval_empty () : Lemma
  (ensures (byte_val 0x42uy).dec Seq.empty == Inl (mk_decode_error UnexpectedEndOfInput 0))
  = ()

/// varint_decode_expected truncated 2-byte: b0 has continuation bit set
/// but only 1 byte of input provided.
let test_varint_truncated_2byte () : Lemma
  (ensures Data.Codec.Pulse.varint_decode_expected
    (seq_of_list [0x80uy])
    0ul 1ul
    == Data.Codec.Pulse.DR_Inl ({code=Data.Codec.Pulse.EC_UnexpectedEndOfInput; pos=0ul}))
  = let result = Data.Codec.Pulse.varint_decode_expected (seq_of_list [0x80uy]) 0ul 1ul in
    assert (Data.Codec.Pulse.DR_Inl? result);
    let Data.Codec.Pulse.DR_Inl err = result in
    assert (err.code == Data.Codec.Pulse.EC_UnexpectedEndOfInput);
    assert (err.pos == 0ul);
    ()

/// varint_decode_expected truncated 3-byte: b0 and b1 have continuation bits
/// set but only 2 bytes of input provided.
let test_varint_truncated_3byte () : Lemma
  (ensures Data.Codec.Pulse.varint_decode_expected
    (seq_of_list [0x80uy; 0x80uy])
    0ul 2ul
    == Data.Codec.Pulse.DR_Inl ({code=Data.Codec.Pulse.EC_UnexpectedEndOfInput; pos=0ul}))
  = let result = Data.Codec.Pulse.varint_decode_expected (seq_of_list [0x80uy; 0x80uy]) 0ul 2ul in
    assert (Data.Codec.Pulse.DR_Inl? result);
    let Data.Codec.Pulse.DR_Inl err = result in
    assert (err.code == Data.Codec.Pulse.EC_UnexpectedEndOfInput);
    assert (err.pos == 0ul);
    ()

/// varint_decode_expected truncated 4-byte: b0,b1,b2 have continuation bits
/// set but only 3 bytes of input provided.
let test_varint_truncated_4byte () : Lemma
  (ensures Data.Codec.Pulse.varint_decode_expected
    (seq_of_list [0x80uy; 0x80uy; 0x80uy])
    0ul 3ul
    == Data.Codec.Pulse.DR_Inl ({code=Data.Codec.Pulse.EC_UnexpectedEndOfInput; pos=0ul}))
  = let result = Data.Codec.Pulse.varint_decode_expected (seq_of_list [0x80uy; 0x80uy; 0x80uy]) 0ul 3ul in
    assert (Data.Codec.Pulse.DR_Inl? result);
    let Data.Codec.Pulse.DR_Inl err = result in
    assert (err.code == Data.Codec.Pulse.EC_UnexpectedEndOfInput);
    assert (err.pos == 0ul);
    ()

/// varint_decode_expected truncated 5-byte: b0,b1,b2,b3 have continuation bits
/// set but only 4 bytes of input provided.
let test_varint_truncated_5byte () : Lemma
  (ensures Data.Codec.Pulse.varint_decode_expected
    (seq_of_list [0x80uy; 0x80uy; 0x80uy; 0x80uy])
    0ul 4ul
    == Data.Codec.Pulse.DR_Inl ({code=Data.Codec.Pulse.EC_UnexpectedEndOfInput; pos=0ul}))
  = let result = Data.Codec.Pulse.varint_decode_expected (seq_of_list [0x80uy; 0x80uy; 0x80uy; 0x80uy]) 0ul 4ul in
    assert (Data.Codec.Pulse.DR_Inl? result);
    let Data.Codec.Pulse.DR_Inl err = result in
    assert (err.code == Data.Codec.Pulse.EC_UnexpectedEndOfInput);
    assert (err.pos == 0ul);
    ()

(** Missing negative tests *)

/// choice(c2-only): roundtrip when c1.wfcv is false and c2 covers the value.
/// satisfy-predicate on 0x42 fails for 0x43, so choice falls through to token.
let test_choice_c2_roundtrip () : Lemma
  (ensures (choice (satisfy (fun b -> U8.v b = 0x42)) token).dec
    ((choice (satisfy (fun b -> U8.v b = 0x42)) token).enc 0x43uy `Seq.append` Seq.empty)
    == Inr (0x43uy, 2))
  = (choice (satisfy (fun b -> U8.v b = 0x42)) token).roundtrip 0x43uy Seq.empty

/// map_ with apply returning None: decode succeeds but apply fails → ExpectedPredicate.
let test_map_none_decode () : Lemma
  (ensures (map_ (fun b -> None) (fun i -> Some (U8.uint_to_t (i % 256))) token).dec
    (token.enc 0x42uy) == Inl (mk_decode_error ExpectedPredicate 0))
  = (* token.dec succeeds on [0x42uy] → Inr (0x42uy, 1).
       map_.apply 0x42uy = None → Inl ExpectedPredicate. *)
    lemma_create_len 1 0x42uy;
    assert (token.dec (token.enc 0x42uy) == Inr (0x42uy, 1));
    ()

/// digits_to_int failure: 'G' (0x47) is not a digit byte (0x30-0x39).
let test_digits_to_int_failure () : Lemma
  (ensures (digits_to_int 4 (fun n -> n < 2000)).dec
    (seq_of_list [0x47uy; 0x47uy; 0x47uy; 0x47uy])
    == Inl (mk_decode_error ExpectedPredicate 0))
  = (* 0x47 = 71, outside [0x30,0x39] = [48,57].  is_digit check fails at byte 0. *)
    assert_norm (is_digit 0x47uy == false);
    ()

/// label error propagation: error through label preserves error code + adds label field.
let test_label_error_propagation () : Lemma
  (ensures (label "test-label" token).dec Seq.empty
    == Inl ({mk_decode_error UnexpectedEndOfInput 0 with label = Some "test-label"}))
  = (* token.dec on empty input → UnexpectedEndOfInput.
       label wraps the error with label=Some "test-label". *)
    assert (token.dec Seq.empty == Inl (mk_decode_error UnexpectedEndOfInput 0));
    ()

/// word16le truncation: 1 byte input → UnexpectedEndOfInput.
let test_decode_truncated_word16le () : Lemma
  (ensures word16le.dec (Seq.create 1 0x00uy) == Inl (mk_decode_error UnexpectedEndOfInput 1))
  = (* word16le.dec needs 2 bytes, has 1 — length check fails at pos=1. *)
    assert_norm (Seq.length (Seq.create 1 0x00uy) == 1);
    ()

/// word32le truncation: 2 bytes input → UnexpectedEndOfInput.
let test_decode_truncated_word32le () : Lemma
  (ensures word32le.dec (Seq.create 2 0x00uy) == Inl (mk_decode_error UnexpectedEndOfInput 2))
  = (* word32le.dec needs 4 bytes, has 2 — length check fails at pos=2. *)
    assert_norm (Seq.length (Seq.create 2 0x00uy) == 2);
    ()

#pop-options

(** Stack-based roundtrip tests — exercise Pulse buffer code path *)

#push-options "--z3rlimit 40"

/// Stack-based roundtrip: token encode→decode through Pulse buffer.
let test_stack_token_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 2ul in
    let (_, result) = lemma_pulse_roundtrip_token 0x42ul buf 0ul 2ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: uint8 encode→decode through Pulse buffer.
let test_stack_uint8_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 2ul in
    let (_, result) = lemma_pulse_roundtrip_uint8 42ul buf 0ul 2ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: byte_val encode→decode through Pulse buffer.
let test_stack_byteval_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 2ul in
    let (_, result) = lemma_pulse_roundtrip_byteval 0x5Buy buf 0ul 2ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: word16be encode→decode through Pulse buffer.
let test_stack_word16be_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 3ul in
    let (_, result) = lemma_pulse_roundtrip_word16be 0xABCDul buf 0ul 3ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: word32be encode→decode through Pulse buffer.
let test_stack_word32be_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 5ul in
    let (_, result) = lemma_pulse_roundtrip_word32be 0xDEADBEEFul buf 0ul 5ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: word16le encode→decode through Pulse buffer.
let test_stack_word16le_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 3ul in
    let (_, result) = lemma_pulse_roundtrip_word16le 0xCDABul buf 0ul 3ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: word32le encode→decode through Pulse buffer.
let test_stack_word32le_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 5ul in
    let (_, result) = lemma_pulse_roundtrip_word32le 0xEFBEADDEul buf 0ul 5ul in
    assert (Data.Codec.Pulse.DR_Inr? result);
    pop_frame ();
    ()

/// Stack-based roundtrip: varint encode→decode through Pulse buffer.
/// Tests 5-range varint encoding (1..5 bytes) with concrete boundary values.
let test_stack_varint_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 6ul in
    let (_, result_0) = lemma_pulse_roundtrip_varint 0ul buf 0ul 6ul in
    assert (Data.Codec.Pulse.DR_Inr? result_0);
    let (_, result_128) = lemma_pulse_roundtrip_varint 128ul buf 0ul 6ul in
    assert (Data.Codec.Pulse.DR_Inr? result_128);
    let (_, result_16384) = lemma_pulse_roundtrip_varint 16384ul buf 0ul 6ul in
    assert (Data.Codec.Pulse.DR_Inr? result_16384);
    let (_, result_2097152) = lemma_pulse_roundtrip_varint 2097152ul buf 0ul 6ul in
    assert (Data.Codec.Pulse.DR_Inr? result_2097152);
    let (_, result_268435456) = lemma_pulse_roundtrip_varint 268435456ul buf 0ul 6ul in
    assert (Data.Codec.Pulse.DR_Inr? result_268435456);
    pop_frame ();
    ()

/// Stack-based error test: decode_varint overflow detection.
let test_stack_varint_overflow () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 5ul in
    (* Write 5-byte overflow: b0..b3 all continuation, b4=0x10 > 15 *)
    LB.upd buf 0ul 0xFFuy;
    LB.upd buf 1ul 0xFFuy;
    LB.upd buf 2ul 0xFFuy;
    LB.upd buf 3ul 0xFFuy;
    LB.upd buf 4ul 0x10uy;
    let result = decode_varint buf 0ul 5ul in
    assert (Data.Codec.Pulse.DR_Inl? result);
    pop_frame ();
    ()

/// Stack-based roundtrip through dispatch table: encode_bytes CT_Varint → decode_bytes CT_Varint.
let test_stack_varint_dispatch_roundtrip () : Stack unit
  (requires fun _ -> True) (ensures fun _ _ _ -> True)
  = push_frame ();
    let buf = alloca 0uy 6ul in
    let v = 300ul in
    let written = encode_bytes CT_Varint v buf 0ul in
    let result = decode_bytes CT_Varint buf 0ul written in
    assert (Data.Codec.Pulse.DR_Inr? result);
    let Data.Codec.Pulse.DR_Inr r = result in
    assert (r.value == v);
    pop_frame ();
    ()

#pop-options

(** Concrete char predicate tests *)

#push-options "--z3rlimit 20"

/// is_digit: byte 0x30 ('0') is a digit.
let test_is_digit_byte_0x30 () : Lemma (ensures is_digit 0x30uy == true) = ()

/// is_digit: byte 0x47 ('G') is not a digit.
let test_is_digit_byte_0x47 () : Lemma (ensures is_digit 0x47uy == false) = ()

/// is_upper: byte 0x41 ('A') is upper.
let test_is_upper () : Lemma (ensures is_upper 0x41uy == true) = ()

/// is_upper: byte 0x61 ('a') is not upper.
let test_is_upper_false () : Lemma (ensures is_upper 0x61uy == false) = ()

/// is_lower: byte 0x61 ('a') is lower.
let test_is_lower () : Lemma (ensures is_lower 0x61uy == true) = ()

/// is_lower: byte 0x41 ('A') is not lower.
let test_is_lower_false () : Lemma (ensures is_lower 0x41uy == false) = ()

/// is_alpha: byte 0x41 ('A') is alpha.
let test_is_alpha () : Lemma (ensures is_alpha 0x41uy == true) = ()

/// is_alpha: byte 0x30 ('0') is not alpha.
let test_is_alpha_false () : Lemma (ensures is_alpha 0x30uy == false) = ()

/// is_alphanum: byte 0x30 ('0') is alphanumeric.
let test_is_alphanum () : Lemma (ensures is_alphanum 0x30uy == true) = ()

/// is_alphanum: byte 0x5B ('[') is not alphanumeric.
let test_is_alphanum_false () : Lemma (ensures is_alphanum 0x5Buy == false) = ()

/// is_space_or_tab: byte 0x20 (space) is space_or_tab.
let test_is_space_or_tab () : Lemma (ensures is_space_or_tab 0x20uy == true) = ()

/// is_space_or_tab: byte 0x41 ('A') is not space_or_tab.
let test_is_space_or_tab_false () : Lemma (ensures is_space_or_tab 0x41uy == false) = ()

/// is_whitespace: byte 0x0A (LF) is whitespace.
let test_is_whitespace () : Lemma (ensures is_whitespace 0x0Auy == true) = ()

/// is_whitespace: byte 0x41 ('A') is not whitespace.
let test_is_whitespace_false () : Lemma (ensures is_whitespace 0x41uy == false) = ()

/// is_printable: byte 0x7E ('~') is printable.
let test_is_printable () : Lemma (ensures is_printable 0x7Euy == true) = ()

/// is_printable: byte 0x1F (control) is not printable.
let test_is_printable_false () : Lemma (ensures is_printable 0x1Fuy == false) = ()

/// char_is_digit: '9' is a digit char.
let test_char_is_digit () : Lemma
  (ensures char_is_digit '9' == true) = ()

/// char_is_upper: 'Z' is uppercase.
let test_char_is_upper () : Lemma
  (ensures char_is_upper 'Z' == true) = ()

/// char_is_lower: 'z' is lowercase.
let test_char_is_lower () : Lemma
  (ensures char_is_lower 'z' == true) = ()

/// char_is_alpha: 'M' is alphabetic.
let test_char_is_alpha () : Lemma
  (ensures char_is_alpha 'M' == true) = ()

/// digit_byte: a satisfy combinator on is_digit.
let test_digit_byte_roundtrip () : Lemma
  (ensures digit_byte.dec (digit_byte.enc 0x35uy `Seq.append` Seq.empty) == Inr (0x35uy, 1))
  = digit_byte.roundtrip 0x35uy Seq.empty

#pop-options

(** Derived combinator tests *)

#push-options "--z3rlimit 40"

/// custom: trivial wrapper around token — proves the extension point composes.
let test_custom_roundtrip () : Lemma
  (ensures (custom token.dec token.enc token.wfcv token.wfcv_prop token.rest_cond
                  token.roundtrip token.dec_err_bound token.dec_consumed_bound).dec
    ((custom token.dec token.enc token.wfcv token.wfcv_prop token.rest_cond
           token.roundtrip token.dec_err_bound token.dec_consumed_bound).enc 0x42uy
     `Seq.append` Seq.empty)
    == Inr (0x42uy, 1))
  = let c = custom token.dec token.enc token.wfcv token.wfcv_prop token.rest_cond
              token.roundtrip token.dec_err_bound token.dec_consumed_bound in
    c.roundtrip 0x42uy Seq.empty

/// then_drop: token *> uint8 roundtrip.
let test_then_drop_roundtrip () : Lemma
  (ensures (then_drop (byte_val 0x2Auy) uint8).dec
    ((then_drop (byte_val 0x2Auy) uint8).enc 7 `Seq.append` Seq.empty)
    == Inr (7, 2))
  = (then_drop (byte_val 0x2Auy) uint8).roundtrip 7 Seq.empty

/// drop_then: uint8 <* token roundtrip.
let test_drop_then_roundtrip () : Lemma
  (ensures (drop_then uint8 (byte_val 0x2Auy)).dec
    ((drop_then uint8 (byte_val 0x2Auy)).enc 7 `Seq.append` Seq.empty)
    == Inr (7, 2))
  = (drop_then uint8 (byte_val 0x2Auy)).roundtrip 7 Seq.empty

/// take: exactly 2 bytes.
let test_take_roundtrip () : Lemma
  (ensures (take 2).dec ((take 2).enc [0x01uy; 0x02uy] `Seq.append` Seq.empty)
    == Inr ([0x01uy; 0x02uy], 2))
  = (take 2).roundtrip [0x01uy; 0x02uy] Seq.empty

/// word16le pure roundtrip.
let test_word16le_roundtrip () : Lemma
  (ensures word16le.dec (word16le.enc 0xABCD `Seq.append` Seq.empty) == Inr (0xABCD, 2))
  = word16le.roundtrip 0xABCD Seq.empty

/// word32le pure roundtrip.
let test_word32le_roundtrip () : Lemma
  (ensures word32le.dec (word32le.enc 0xDEADBEEF `Seq.append` Seq.empty) == Inr (0xDEADBEEF, 4))
  = word32le.roundtrip 0xDEADBEEF Seq.empty

/// sum Inr roundtrip.
let test_sum_roundtrip_inr () : Lemma
  (ensures (sum token uint8).dec
    ((sum token uint8).enc (Inr 7) `Seq.append` Seq.empty)
    == Inr (Inr 7, 2))
  = lemma_seq_cons_append 0x01uy (uint8.enc 7) Seq.empty;
    uint8.roundtrip 7 Seq.empty;
    lemma_slice_cons_spec 0x01uy (uint8.enc 7 `Seq.append` Seq.empty);
    ()

#pop-options

(** Derived combinator error path tests *)

#push-options "--z3rlimit 40"

/// between: open_ byte mismatch.
let test_between_open_error () : Lemma
  (ensures (between (byte_val 0x5Buy) (byte_val 0x5Duy) uint8).dec
    (seq_of_list [0x00uy; 0x2Auy; 0x5Duy])
    == Inl (mk_decode_error (ExpectedByte 0x5Buy) 0))
  = ()

/// between: close byte mismatch.
let test_between_close_error () : Lemma
  (ensures (between (byte_val 0x5Buy) (byte_val 0x5Duy) uint8).dec
    (seq_of_list [0x5Buy; 0x2Auy; 0x00uy])
    == Inl (mk_decode_error (ExpectedByte 0x5Duy) 2))
  = ()

/// optional: bad tag byte (neither 0x00 nor 0x01).
let test_optional_bad_tag () : Lemma
  (ensures (optional uint8).dec (seq_of_list [0x02uy; 0x2Auy])
    == Inl (mk_decode_error ExpectedSumTag 0))
  = ()

/// choice: encoding without any wfcv produces empty encoding.
let test_choice_neither_wfcv_enc () : Lemma
  (ensures (choice (satisfy (fun b -> U8.v b = 0x42)) (satisfy (fun b -> U8.v b = 0x42))).enc 0x43uy
    == Seq.empty)
  = assert (U8.v 0x43uy <> 0x42);
    ()

/// product: c1 succeeds, c2 fails — error position offset.
let test_product_c2_fails () : Lemma
  (ensures (product token (byte_val 0xFFuy)).dec
    (seq_of_list [0x2Auy; 0x00uy])
    == Inl (mk_decode_error (ExpectedByte 0xFFuy) 1))
  = ()

/// count: sub-decoder fails on 3rd element.
let test_count_mid_failure () : Lemma
  (ensures (Data.Codec.Types.count 3 (byte_val 0x42uy)).dec
    (seq_of_list [0x42uy; 0x42uy; 0x00uy])
    == Inl (mk_decode_error (ExpectedByte 0x42uy) 2))
  = ()

/// text: truncated input (shorter than expected string).
let test_text_truncated () : Lemma
  (ensures (text "ABC").dec (seq_of_list [0x41uy; 0x42uy])
    == Inl (mk_decode_error ExpectedEndOfInput 2))
  = assert_norm (string_to_bytes "ABC" == seq_of_list [0x41uy; 0x42uy; 0x43uy]);
    assert_norm (Seq.length (seq_of_list [0x41uy; 0x42uy]) == 2);
    ()

/// bytes: input shorter than expected byte list.
let test_bytes_truncated () : Lemma
  (ensures (bytes [0x00uy; 0x01uy; 0x02uy]).dec (seq_of_list [0x00uy; 0x01uy])
    == Inl (mk_decode_error UnexpectedEndOfInput 2))
  = ()

/// sum: Inl branch — sub-decoder fails (inner token needs >=1 byte).
let test_sum_inl_decode_fails () : Lemma
  (ensures (sum token token).dec (Seq.cons 0x00uy Seq.empty)
    == Inl (mk_decode_error UnexpectedEndOfInput 1))
  = ()

/// label: successful decode passes through unchanged.
let test_label_success () : Lemma
  (ensures (label "test" uint8).dec (uint8.enc 42) == Inr (42, 1))
  = uint8.roundtrip 42 Seq.empty;
    lemma_slice_after_prefix (uint8.enc 42) Seq.empty;
    ()

#pop-options

(** Remaining combinator gap tests *)

#push-options "--z3rlimit 40"

/// pure roundtrip: always succeeds, encodes as empty bytes.
let test_pure_roundtrip () : Lemma
  (ensures (pure 42).dec ((pure 42).enc 42 `Seq.append` Seq.empty) == Inr (42, 0))
  = (pure 42).roundtrip 42 Seq.empty

/// satisfy roundtrip on a valid byte.
let test_satisfy_roundtrip () : Lemma
  (ensures (satisfy (fun b -> U8.v b = 0x42)).dec
    ((satisfy (fun b -> U8.v b = 0x42)).enc 0x42uy `Seq.append` Seq.empty)
    == Inr (0x42uy, 1))
  = (satisfy (fun b -> U8.v b = 0x42)).roundtrip 0x42uy Seq.empty

/// satisfy on empty input → UnexpectedEndOfInput.
let test_satisfy_empty () : Lemma
  (ensures (satisfy (fun b -> U8.v b = 0x42)).dec Seq.empty
    == Inl (mk_decode_error UnexpectedEndOfInput 0))
  = ()

/// custom error path: custom dec = token.dec — delegates to token, so
/// dec Seq.empty = token.dec Seq.empty = UnexpectedEndOfInput.
let test_custom_error () : Lemma
  (ensures (custom token.dec token.enc token.wfcv token.wfcv_prop token.rest_cond
                  token.roundtrip token.dec_err_bound token.dec_consumed_bound).dec Seq.empty
    == Inl (mk_decode_error UnexpectedEndOfInput 0))
  = ()

/// then_drop: c1 fails mid-decode (wrong byte).
let test_then_drop_c1_fails () : Lemma
  (ensures (then_drop (byte_val 0x42uy) uint8).dec
    (seq_of_list [0x00uy; 0x2Auy])
    == Inl (mk_decode_error (ExpectedByte 0x42uy) 0))
  = ()

/// drop_then: c2 fails mid-decode (wrong byte at suffix position).
let test_drop_then_c2_fails () : Lemma
  (ensures (drop_then uint8 (byte_val 0x42uy)).dec
    (seq_of_list [0x2Auy; 0x00uy])
    == Inl (mk_decode_error (ExpectedByte 0x42uy) 1))
  = ()

/// take: input shorter than n.
let test_take_truncated () : Lemma
  (ensures (take 3).dec (seq_of_list [0x01uy; 0x02uy])
    == Inl (mk_decode_error UnexpectedEndOfInput 2))
  = ()

#pop-options

(** Char predicate gaps: missing positive + false tests *)

#push-options "--z3rlimit 20"

let test_char_is_digit_false () : Lemma (ensures char_is_digit 'A' == false) = ()
let test_char_is_upper_false () : Lemma (ensures char_is_upper 'a' == false) = ()
let test_char_is_lower_false () : Lemma (ensures char_is_lower 'A' == false) = ()
let test_char_is_alpha_false () : Lemma (ensures char_is_alpha '0' == false) = ()
let test_char_is_alphanum () : Lemma (ensures char_is_alphanum 'a' == true) = ()
let test_char_is_alphanum_false () : Lemma (ensures char_is_alphanum '[' == false) = ()
let test_char_is_space_or_tab () : Lemma (ensures char_is_space_or_tab ' ' == true) = ()
let test_char_is_space_or_tab_false () : Lemma (ensures char_is_space_or_tab 'A' == false) = ()
let test_char_is_whitespace () : Lemma (ensures char_is_whitespace '\n' == true) = ()
let test_char_is_whitespace_false () : Lemma (ensures char_is_whitespace 'A' == false) = ()
let test_char_is_printable () : Lemma (ensures char_is_printable '~' == true) = ()
let test_char_is_printable_false () : Lemma (ensures char_is_printable '\x1F' == false) = ()

/// digit_byte error: non-digit byte → ExpectedPredicate.
let test_digit_byte_error () : Lemma
  (ensures digit_byte.dec (seq_of_list [0x47uy]) == Inl (mk_decode_error ExpectedPredicate 0))
  = ()

#pop-options
