(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(* Spike for the Pulse port of Data.Codec.Low.

   Minimal: encode_token / decode_token only, mirroring the pure-spec
   correspondence of Data.Codec.Types.token.  NOT wired into the build. *)

module Data.Codec.Spike
#lang-pulse

open Pulse
open Pulse.Lib.Reference
module A = Pulse.Lib.Array
module US = FStar.SizeT
module U8 = FStar.UInt8
module U32 = FStar.UInt32
module Seq = FStar.Seq

open FStar.Seq
open FStar.Int.Cast

(* ── encode_token: one byte ─────────────────────────────────────────── *)

fn encode_token (v: U32.t) (b: A.array U8.t) (i: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + 1 <= A.length b /\
        U32.v v < 256)
    returns w: U32.t
    ensures
      (exists* (s1: Seq.seq U8.t).
        A.pts_to b s1 **
        pure (
          U32.v i + 1 <= A.length b /\
          Seq.length s1 == A.length b /\
          Seq.slice s1 (U32.v i) (U32.v i + 1)
            `Seq.equal` Seq.create 1 (uint32_to_uint8 v))) **
      pure (w == 1ul)
{
  let x : U8.t = uint32_to_uint8 v;
  let j : US.t = US.uint32_to_sizet i;
  A.pts_to_len b;
  b.(j) <- x;
  1ul
}

(* ── decode result: small tagged union ──────────────────────────────── *)

type decode_res =
  | Dr_ok of U32.t & U32.t   (* n, value *)
  | Dr_eof of U32.t          (* pos *)

(* ── decode_token: one byte, mirroring token.dec ────────────────────── *)

fn decode_token (b: A.array U8.t) (i: U32.t) (n: U32.t)
    (#s0: erased (Seq.seq U8.t))
    requires
      A.pts_to b s0 **
      pure (
        U32.v i + U32.v n <= A.length b /\
        U32.v i + U32.v n < 4294967296)
    returns r: decode_res
    ensures
      A.pts_to b s0 **
      pure (
        r == Dr_eof i ==> U32.v n == 0)
{
  A.pts_to_len b;
  if U32.lt i (U32.add i n) {
    let j : US.t = US.uint32_to_sizet i;
    let x = b.(j);
    Dr_ok (1ul, uint8_to_uint32 x)
  } else {
    Dr_eof i
  }
}
