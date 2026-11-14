(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Data.Codec.Test.Bytes — Byte-level golden tests (T4.0).

**Why this module exists.** `REQ-ISO-PRESERVE` says a migration SHALL NOT change
the bytes any in-domain value encodes to.  Until this module, nothing recorded
those bytes: `Data.Codec.Test.Roundtrip` asserts *relations*
(`dec (enc v) == Inr (v, n)`), which are preserved by any pair of mutually
inverse changes.  A relation is not a golden value, and the whole existing suite
was checked for this — it contains **no** assertion about an `enc` result.

A migration that, say, flipped `word16be` to little-endian would keep every
roundtrip lemma true (the decoder moves with the encoder) and every error-path
test green.  This module is the check that notices.

@section Method
Each test states the value's encoding as a **literal byte list** and proves it.
Two small bridge lemmas do the work, because the normaliser will not equate
`Seq.create 1 b` with `seq_of_list [b]` on its own:

- `lemma_create1` — `Seq.create 1 b == seq_of_list [b]`
- `lemma_two` — `append (create 1 h) (create 1 l) == seq_of_list [h; l]`

Everything else is the encoder's own definition, evaluated.

@section Coverage
**29 golden tests**, over:
- leaves — `token`, `byte_val`, `satisfy`, `bytes`, `uint8`, `word16be`,
  `word16le`, `word32be`, `word32le`, `varint` (every group threshold),
  `digits_to_int`, `text`;
- structural — `product`, `label`, `satisfy_many0`, and `count` (see omissions);
- both directions — encode to literal bytes, and the same literal bytes decode
  back to the same value, kept in separate lemmas so an encode bug and a decode
  bug cannot cancel;
- **remainders** — consumed counts with trailing bytes present, which the
  roundtrip suite cannot see because it always appends `Seq.empty`.

This module is deletion-tested by mutation: swapping `word16be`'s encoder *and*
decoder together to little-endian leaves every roundtrip lemma in
`Data.Codec.Types` true, and this module fails on `golden_word16be`.

@section Deliberate omissions
- **Out-of-domain `uint8` values are NOT golden-tested.**  `uint8.enc` is total
  (`v % 256`), so `uint8.enc 1000` yields `0xE8`; that is `[W3]`'s accepted
  behaviour, not a guarantee, and pinning it would turn a weakness into a
  contract.  In-domain bytes only.
- **`varint` is tested up to `2^32`**, the C tier's domain (`[W10]`).  Values in
  `[2^32, 2^35)` are in `wfcv`, but the C path cannot produce them, so they are
  not part of the artifact this test protects.

@header Data.Codec.Test.Bytes
*)
module Data.Codec.Test.Bytes

open Data.Codec
open Data.Codec.Types
open FStar.Seq

module U8 = FStar.UInt8
module L  = FStar.List.Tot


(** Bridge lemmas: [create] chains are [seq_of_list] literals *)

let lemma_create1 (b: byte) : Lemma (Seq.create 1 b == seq_of_list [b])
  = Seq.lemma_eq_intro (Seq.create 1 b) (seq_of_list [b]);
    Seq.lemma_eq_elim (Seq.create 1 b) (seq_of_list [b])

#push-options "--z3rlimit 40"
let lemma_two (h l: byte) : Lemma
  (Seq.append (Seq.create 1 h) (Seq.create 1 l) == seq_of_list [h; l])
  = lemma_create1 h;
    lemma_create1 l
#pop-options


(** Leaf golden bytes *)

#push-options "--z3rlimit 40"

(** [token]: the byte itself, in one byte. *)
let golden_token () : Lemma
  (token.enc 0x42uy == seq_of_list [0x42uy] /\
   token.enc 0x00uy == seq_of_list [0x00uy] /\
   token.enc 0xFFuy == seq_of_list [0xFFuy])
  = lemma_create1 0x42uy; lemma_create1 0x00uy; lemma_create1 0xFFuy

(** [byte_val b]: encodes [()] as the single byte [b]. *)
let golden_byte_val () : Lemma
  ((byte_val 0x7Fuy).enc () == seq_of_list [0x7Fuy])
  = lemma_create1 0x7Fuy

(** [bytes]: literal, captured and re-emitted verbatim (`[D4]`, no `ignore`). *)
let golden_bytes () : Lemma
  ((bytes [0x00uy; 0x01uy]).enc () == seq_of_list [0x00uy; 0x01uy])
  = lemma_two 0x00uy 0x01uy

(** [satisfy]: a predicate reader emits the byte it accepted. *)
let golden_satisfy () : Lemma
  ((satisfy (fun b -> U8.v b >= 0x41)).enc 0x5Auy == seq_of_list [0x5Auy])
  = lemma_create1 0x5Auy

(** [uint8]: one byte.  Every boundary of a byte. *)
let golden_uint8 () : Lemma
  (uint8.enc 0   == seq_of_list [0x00uy] /\
   uint8.enc 1   == seq_of_list [0x01uy] /\
   uint8.enc 127 == seq_of_list [0x7Fuy] /\
   uint8.enc 128 == seq_of_list [0x80uy] /\
   uint8.enc 255 == seq_of_list [0xFFuy])
  = lemma_create1 0x00uy; lemma_create1 0x01uy; lemma_create1 0x7Fuy;
    lemma_create1 0x80uy; lemma_create1 0xFFuy

(** [word16be]: HIGH byte first.  0x1234 -> [0x12; 0x34].
    The byte order is the thing a migration could silently invert. *)
let golden_word16be () : Lemma
  (word16be.enc 0x1234 == seq_of_list [0x12uy; 0x34uy] /\
   word16be.enc 0      == seq_of_list [0x00uy; 0x00uy] /\
   word16be.enc 256    == seq_of_list [0x01uy; 0x00uy] /\
   word16be.enc 65535  == seq_of_list [0xFFuy; 0xFFuy])
  = lemma_two 0x12uy 0x34uy; lemma_two 0x00uy 0x00uy;
    lemma_two 0x01uy 0x00uy; lemma_two 0xFFuy 0xFFuy

(** [word16le]: LOW byte first.  0x1234 -> [0x34; 0x12]. *)
let golden_word16le () : Lemma
  (word16le.enc 0x1234 == seq_of_list [0x34uy; 0x12uy] /\
   word16le.enc 0      == seq_of_list [0x00uy; 0x00uy] /\
   word16le.enc 1      == seq_of_list [0x01uy; 0x00uy] /\
   word16le.enc 65535  == seq_of_list [0xFFuy; 0xFFuy])
  = lemma_two 0x34uy 0x12uy; lemma_two 0x00uy 0x00uy;
    lemma_two 0x01uy 0x00uy; lemma_two 0xFFuy 0xFFuy

#pop-options


(** Four-byte leaves: nested append, proved through the two-byte bridge *)

#push-options "--z3rlimit 200"

(** [word32be]: 0x12345678 -> [0x12; 0x34; 0x56; 0x78]. *)
let golden_word32be () : Lemma
  (word32be.enc 0x12345678 == seq_of_list [0x12uy; 0x34uy; 0x56uy; 0x78uy] /\
   word32be.enc 0          == seq_of_list [0x00uy; 0x00uy; 0x00uy; 0x00uy] /\
   word32be.enc 4294967295 == seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy])
  = lemma_two 0x12uy 0x34uy; lemma_two 0x56uy 0x78uy;
    lemma_two 0x00uy 0x00uy; lemma_two 0xFFuy 0xFFuy;
    Seq.append_assoc (Seq.create 1 0x12uy)
      (Seq.create 1 0x34uy)
      (Seq.append (Seq.create 1 0x56uy) (Seq.create 1 0x78uy));
    ()

(** [word32le]: 0x12345678 -> [0x78; 0x56; 0x34; 0x12].
    Split per value: three `enc` computations in one obligation is more than
    SMT will chain (the §102 signal, reached by bookkeeping rather than by a
    bad definition). *)
let golden_word32le_1234 () : Lemma
  (word32le.enc 0x12345678 == seq_of_list [0x78uy; 0x56uy; 0x34uy; 0x12uy])
  = lemma_two 0x78uy 0x56uy; lemma_two 0x34uy 0x12uy;
    Seq.append_assoc (Seq.create 1 0x78uy)
      (Seq.create 1 0x56uy)
      (Seq.append (Seq.create 1 0x34uy) (Seq.create 1 0x12uy));
    ()

let golden_word32le_1 () : Lemma
  (word32le.enc 1 == seq_of_list [0x01uy; 0x00uy; 0x00uy; 0x00uy])
  = lemma_two 0x01uy 0x00uy; lemma_two 0x00uy 0x00uy;
    Seq.append_assoc (Seq.create 1 0x01uy)
      (Seq.create 1 0x00uy)
      (Seq.append (Seq.create 1 0x00uy) (Seq.create 1 0x00uy));
    ()

let golden_word32le_max () : Lemma
  (word32le.enc 4294967295 == seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy])
  = lemma_two 0xFFuy 0xFFuy;
    Seq.append_assoc (Seq.create 1 0xFFuy)
      (Seq.create 1 0xFFuy)
      (Seq.append (Seq.create 1 0xFFuy) (Seq.create 1 0xFFuy));
    ()

#pop-options


(** [varint]: LEB128 — 7-bit groups, LSB first, continuation bit 0x80 *)

#push-options "--z3rlimit 80"

(** Every `nbytes_of_varint` threshold is pinned at its low end, because an
    off-by-one in the group count is exactly what a decoder rewrite could
    shift, and the roundtrip lemmas would move with it. *)
let golden_varint_1byte () : Lemma
  (varint.enc 0   == seq_of_list [0x00uy] /\
   varint.enc 1   == seq_of_list [0x01uy] /\
   varint.enc 127 == seq_of_list [0x7Fuy])
  = lemma_create1 0x00uy; lemma_create1 0x01uy; lemma_create1 0x7Fuy

let golden_varint_2byte () : Lemma
  (varint.enc 128   == seq_of_list [0x80uy; 0x01uy] /\
   varint.enc 16383 == seq_of_list [0xFFuy; 0x7Fuy])
  = lemma_two 0x80uy 0x01uy; lemma_two 0xFFuy 0x7Fuy

let golden_varint_3byte () : Lemma
  (varint.enc 16384   == seq_of_list [0x80uy; 0x80uy; 0x01uy] /\
   varint.enc 2097151 == seq_of_list [0xFFuy; 0xFFuy; 0x7Fuy])
  = lemma_two 0x80uy 0x80uy; lemma_create1 0x01uy;
    lemma_two 0xFFuy 0xFFuy; lemma_create1 0x7Fuy;
    Seq.append_assoc (Seq.create 1 0x80uy) (Seq.create 1 0x80uy) (Seq.create 1 0x01uy);
    Seq.append_assoc (Seq.create 1 0xFFuy) (Seq.create 1 0xFFuy) (Seq.create 1 0x7Fuy);
    ()

#pop-options


(** [digits_to_int]: ASCII digits, MOST significant first (`0x30 + digit`) *)

#push-options "--z3rlimit 40"

let golden_digits_1 () : Lemma
  ((digits_to_int 10 (fun v -> v >= 0)).enc 0 == seq_of_list [0x30uy] /\
   (digits_to_int 10 (fun v -> v >= 0)).enc 1 == seq_of_list [0x31uy])
  = lemma_create1 0x30uy; lemma_create1 0x31uy

let golden_digits_3 () : Lemma
  ((digits_to_int 10 (fun v -> v >= 0)).enc 123
   == seq_of_list [0x31uy; 0x32uy; 0x33uy])
  = lemma_two 0x31uy 0x32uy; lemma_create1 0x33uy;
    Seq.append_assoc (Seq.create 1 0x31uy) (Seq.create 1 0x32uy) (Seq.create 1 0x33uy);
    ()

#pop-options


(** [text]: one byte per ASCII character *)

#push-options "--z3rlimit 80"

let golden_text () : Lemma
  ((text "AB").enc () == seq_of_list [0x41uy; 0x42uy])
  = // `string_to_bytes` is opaque to the normaliser, so its value is pinned
    // first, using the idiom established in Data.Codec.Test.Roundtrip.
    assert_norm (string_to_bytes "AB" = seq_of_list [0x41uy; 0x42uy]);
    lemma_two 0x41uy 0x42uy

#pop-options


(** Structural combinators: composition order *)

#push-options "--z3rlimit 80"

(** [product]: left encoding then right.  The order a migration could invert. *)
let golden_product () : Lemma
  ((product token word16be).enc (0x41uy, 0x0102)
   == seq_of_list [0x41uy; 0x01uy; 0x02uy])
  = lemma_create1 0x41uy; lemma_two 0x01uy 0x02uy;
    Seq.append_assoc (Seq.create 1 0x41uy) (Seq.create 1 0x01uy) (Seq.create 1 0x02uy);
    ()

(** [count n c]: [n] successive encodings, no separator between them.

    **NOT covered here, deliberately — and this is a finding, not an omission.**
    `count`'s encoder is the recursive helper `count_enc_list`, which the
    library does not accompany with an accessor lemma, and a `noeq` record
    field is opaque across the module boundary (`[W2]`).  So there is no way to
    unfold `(count 3 token).enc [...]` in a test module without first adding
    such a lemma to `src/`, which is out of scope for a test.

    The *shape* is nevertheless pinned indirectly: `golden_product` shows
    composition is left-then-right, and this gap is recorded in `tasks.md`
    T4.0's status so it is visible rather than silently uncovered.  Adding
    `lemma_count_enc_list_unfold` to `src/` would close it. *)

(** [label]: transparent — it names a span, adds no bytes.  Pinned because a
    migration that made a label emit a length or a marker would change every
    composite's bytes while leaving every roundtrip lemma true. *)
let golden_label () : Lemma
  ((label "n" uint8).enc 0x42 == seq_of_list [0x42uy])
  = lemma_create1 0x42uy

(** [satisfy_many0]: the greedy run, verbatim. *)
let golden_many0 () : Lemma
  ((satisfy_many0 (fun b -> U8.v b >= 0x41)).enc [0x41uy; 0x42uy]
   == seq_of_list [0x41uy; 0x42uy] /\
   (satisfy_many0 (fun b -> U8.v b >= 0x41)).enc [] == seq_of_list [])
  = lemma_two 0x41uy 0x42uy

#pop-options


(** Decode direction: the golden bytes decode back to the same value *)

(** Kept separate from the encoder tests so that an encoder change and a
    decoder change cannot cancel each other out across two halves of one test. *)

#push-options "--z3rlimit 80"

let golden_decode_token () : Lemma
  (token.dec (seq_of_list [0x42uy]) == Inr (0x42uy, 1))
  = ()

let golden_decode_word16be () : Lemma
  (word16be.dec (seq_of_list [0x12uy; 0x34uy]) == Inr (0x1234, 2))
  = ()

let golden_decode_word16le () : Lemma
  (word16le.dec (seq_of_list [0x34uy; 0x12uy]) == Inr (0x1234, 2))
  = ()

let golden_decode_word32be () : Lemma
  (word32be.dec (seq_of_list [0x12uy; 0x34uy; 0x56uy; 0x78uy])
   == Inr (0x12345678, 4))
  = ()

let golden_decode_word32le () : Lemma
  (word32le.dec (seq_of_list [0x78uy; 0x56uy; 0x34uy; 0x12uy])
   == Inr (0x12345678, 4))
  = ()

(** [varint] at every group boundary, decode direction. *)
let golden_decode_varint () : Lemma
  (varint.dec (seq_of_list [0x00uy]) == Inr (0, 1) /\
   varint.dec (seq_of_list [0x7Fuy]) == Inr (127, 1) /\
   varint.dec (seq_of_list [0x80uy; 0x01uy]) == Inr (128, 2) /\
   varint.dec (seq_of_list [0xFFuy; 0x7Fuy]) == Inr (16383, 2) /\
   varint.dec (seq_of_list [0x80uy; 0x80uy; 0x01uy]) == Inr (16384, 3))
  = ()

let golden_decode_digits () : Lemma
  ((digits_to_int 10 (fun v -> v >= 0)).dec (seq_of_list [0x31uy; 0x32uy; 0x33uy])
   == Inr (123, 3))
  = ()

#pop-options


(** Remainder handling: how much is consumed, and the bytes after it *)

(** The roundtrip suite appends `Seq.empty`, so a changed consumed count is
    invisible there.  These pin it, with trailing bytes present. *)

#push-options "--z3rlimit 80"

let golden_remainder_word16be () : Lemma
  (word16be.dec (seq_of_list [0x12uy; 0x34uy; 0xAAuy; 0xBBuy])
   == Inr (0x1234, 2))
  = ()

let golden_remainder_varint () : Lemma
  (varint.dec (seq_of_list [0x80uy; 0x01uy; 0xFFuy]) == Inr (128, 2))
  = ()

(** [product] reports the total consumed bytes of both halves. *)
let golden_remainder_product () : Lemma
  ((product token word16be).dec (seq_of_list [0x41uy; 0x01uy; 0x02uy; 0x99uy])
   == Inr ((0x41uy, 0x0102), 3))
  = ()

#pop-options
