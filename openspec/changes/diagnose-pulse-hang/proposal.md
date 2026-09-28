# Change Proposal: diagnose-pulse-hang

## Summary

`Data.Codec.Pulse` verification **hangs** — `fstar.exe` goes to 0% CPU,
`status = stopped`, and never finishes.  Root-cause it and make the
`.#fstar-codec-checked` / `.#fstar-codec-native` gates terminate (green) again.

## Motivation

The Pulse port of `Data.Codec.Pulse` (formerly `Data.Codec.Low`) verified and
extracted **green earlier in the session** (commit `a34c984` produced
`libfstar-codec.dylib`).  On re-verify, `Data.Codec.Types` and `Data.Codec`
still verify, but the `Data.Codec.Pulse` `fstar.exe` invocation **hangs
forever**: observed at 0% CPU, `status = stopped`, 35+ minutes (probed via
`ps` / `launchctl procinfo`).  This is a **non-terminating SMT query**, not a
type error (type errors return promptly with Error N).

The prime suspects (all observed `--z3rlimit`-sensitive earlier):
- `lemma_pulse_roundtrip_word32be` / `word32le` (division-vs-shift byte
  extraction; the flaky spot that timed out at `--z3rlimit 80`).
- `encode_word32be` / `encode_word32le` (the `Seq.slice s1 == word32*.enc`
  byte-level post-condition).
- `decode_varint` / `varint_decode_expected` (5-way case analysis).

## Scope

- In scope: isolate which `fn`/query hangs, then make it terminate (raise
  per-fn rlimit, add a structural `Lemma`, or replace the inline post-condition
  with a `noextract` helper predicate).
- Out of scope: the T3.2 test-module rewrite (blocked on this fix).

## Definition of done

`nix build .#fstar-codec-checked` and `nix build .#fstar-codec-native` both
terminate and are green at 0-admit, with `Data.Codec.Pulse` verifying.
