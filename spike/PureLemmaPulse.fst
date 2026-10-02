module PureLemmaPulse
#lang-pulse

type r = { a: int; lbl: option string }
let f (x: r) : r = { x with lbl = Some "hi" }
let lem () : Lemma (ensures True) = ()
