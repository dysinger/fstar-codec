(* Spike: Pulse idiom for buffer-based roundtrip tests. *)
module TestIdiom
#lang-pulse

open Pulse
open Pulse.Lib.Reference
module A = Pulse.Lib.Array
module US = FStar.SizeT
module U8 = FStar.UInt8
module U32 = FStar.UInt32
module Seq = FStar.Seq
module Cast = FStar.Int.Cast

open Data.Codec.Pulse

fn test_token (post: unit -> slprop)
    requires emp
    returns u: unit
    ensures emp
{
  A.with_local 0uy 2sz
    (fun buf ->
      let (_, r) = lemma_pulse_roundtrip_token 0x42ul buf 0ul 2ul;
      ())
}
