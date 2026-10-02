module VarintSpike2
open Data.Codec
open Data.Codec.Types
open Data.Codec.Pulse
open FStar.Seq
open FStar.UInt8
open FStar.UInt32

#push-options "--z3rlimit 40"

let test_varint_5byte_oversized () : Lemma
  (ensures (match varint.dec (seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy; 0x10uy]) with
    | Inr (v, _) -> v == 4563402751
    | _ -> False))
  = Data.Codec.Types.lemma_nbytes_of_varint_correct 4563402751;
    Data.Codec.Types.lemma_varint_enc_dec_5byte 4563402751 Seq.empty;
    ()

#pop-options
