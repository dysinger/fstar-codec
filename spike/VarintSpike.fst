module VarintSpike
open Data.Codec
open Data.Codec.Types
open Data.Codec.Pulse
open FStar.Seq

let t () : Lemma
  (ensures (match varint.dec (seq_of_list [0xFFuy; 0xFFuy; 0xFFuy; 0xFFuy; 0x10uy]) with
    | Inr (v, _) -> v == 4563402751
    | _ -> False))
  = lemma_nbytes_of_varint_correct 4563402751;
    lemma_varint_enc_dec_5byte 4563402751 Seq.empty;
    ()
