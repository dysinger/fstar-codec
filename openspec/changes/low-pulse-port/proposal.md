# Change Proposal: low-pulse-port

## Summary

Rewrite the single C leaf module `Data.Codec.Low` from the KaRaMeL Low\*
style (`Stack` effect + `LowStar.Buffer`) to **Pulse** (`fn` +
`Pulse.Lib.*`), so it can extract to C via F\*'s Custard backend
(`--codegen Custard --custard_backend C`) and restore the `native` C target.

## Motivation

The `fstar-roll-forward` change moved the toolchain to F\* `v2026.09.20+lsp`,
which **deleted the entire KaRaMeL/Low\* stdlib** (`FStar.HyperStack`,
`FStar.HyperStack.ST`, `LowStar.Buffer`).  As a result `Data.Codec.Low`
cannot even typecheck anymore, and the old `native`/`krml`/`rust`/`wasm`
targets were removed.  The pure spec (`Data.Codec.Types` + `Data.Codec`)
survives and verifies at 0-admit; only the leaf — and its two test modules —
are dead.

The new F\* ships **Custard**, a whole-program, demand-driven, monomorphizing
extractor.  Its C backend (`--custard_backend C`) emits direct C11 with **no
karamel runtime** and monomorphizes mathematical integers correctly (the
exact failure that forced `int32_t krml_checked_int_t` truncation in the old
path).  But Custard extracts **Pulse** — its builtin buffer rules
(`src/custard/FStarC.Custard.Builtins.fst` `pulse_rule`) cover only
`Pulse.Lib.Reference` / `Vec` / `Array.Core` / `Box` / `ArrayPtr`, with no
`LowStar.Buffer` rule.  So the leaf must be ported to Pulse.

This is a focused source port of one module (~1100 lines); the pure spec is
untouched.

## Scope

- **In scope**:
  - Rewrite `src/Data.Codec.Low.fst` in Pulse: `Stack` → Pulse `fn`,
    `LB.buffer U8.t` → `Pulse.Lib.Vec.vec U8.t` (or `Array`), `LB.upd`/`LB.index`
    → Pulse read/write, and express the `modifies`/`h0 == h1` framing as Pulse
    separation-logic pre/post.
  - Re-verify 0-admit with the leaf + its two test modules restored.
  - Land the `native` C target via `--custard_backend C
    --custard_monomorphize_types true`.
- **Out of scope**:
  - `rust` / `wasm` — no backend in the new F\* (Custard's `KrmlRust` is
    broken upstream; there is no wasm).  Dropped permanently (recorded in the
    `fstar-roll-forward` change).
  - `fsharp` — available (`--custard_backend FSharp`, `.NET 10`) but a
    separate follow-up.
  - Any change to `Data.Codec.Types` / `Data.Codec` (the pure spec).

## Risks

- Pulse is separation-logic-based; proving byte-level post-conditions for the
  8 leaf codecs (esp. `decode_varint`'s 5-range case analysis) may be harder
  than the `Stack` framing it replaces.  Mitigation: port the simplest leaf
  (`encode_token`/`decode_token`) first as a spike to pin the idiom.
- `decode_result_c` (tagged union) returns by value fine in Custard-C, but
  Pulse's `stt` result-representation needs the `[@@extract_as_impure_effect]`
  attribute to be present (already on Pulse's `stt`).
- The two test modules (`Data.Codec.Test.{Roundtrip,Integration}`) reference
  the old Low\* API surface heavily; they must be updated in lockstep.

## Dependencies

- `fstar-roll-forward` (must land first — it provides `v2026.09.20+lsp` with
  Custard, and removes the dead KaRaMeL toolchain).

## Definition of done

`nix build .#fstar-codec-checked` GREEN at 0-admit with the leaf + tests
restored, and `nix build .#fstar-codec-native` GREEN (C11 shared object from
Custard, no karamel).
