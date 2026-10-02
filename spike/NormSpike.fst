module NormSpike
open FStar.Seq
open FStar.UInt8
open Data.Codec.Types

let t () : Lemma ((text "ABC").dec (string_to_bytes "ABD") == Inl (mk_decode_error ExpectedText 0)) =
  let expected = string_to_bytes "ABC" in
  let input = string_to_bytes "ABD" in
  assert_norm (expected == seq_of_list [0x41uy; 0x42uy; 0x43uy]);
  assert_norm (input == seq_of_list [0x41uy; 0x42uy; 0x44uy]);
  assert_norm (Seq.length (seq_of_list [0x41uy; 0x42uy; 0x43uy]) == 3);
  assert_norm (Seq.length (seq_of_list [0x41uy; 0x42uy; 0x44uy]) == 3);
  assert_norm (Seq.slice (seq_of_list [0x41uy; 0x42uy; 0x44uy]) 0 3 == seq_of_list [0x41uy; 0x42uy; 0x44uy]);
  assert_norm (Seq.index (seq_of_list [0x41uy; 0x42uy; 0x43uy]) 2 == 0x43uy);
  assert_norm (Seq.index (seq_of_list [0x41uy; 0x42uy; 0x44uy]) 2 == 0x44uy);
  assert (0x43uy <> 0x44uy);
  ()
