# fstar-codec — Agent Guide & Handoff

`Data.Codec` — verified bidirectional codec library, extracted from the xeno
monorepo (`codec/`) as a standalone repo.  F* source is 0-admit.  This file
records session state and the unfinished Pulse-port work so the next session
resumes cleanly.

## Current state (post Pulse port)

### GREEN (verified this session, F* `v2026.09.20+lsp`)

- `nix build .#fstar-codec-checked` — 0 admits.  Verifies **spec + Pulse leaf**:
  `Data.Codec.Types` + `Data.Codec` + `Data.Codec.Low` (the leaf was rewritten in
  Pulse; see below).
- `nix build .#fstar-codec-ocaml` — pure spec to OCaml findlib (`fstar_codec`).
- `nix build .#fstar-codec-native` — **NEW**: the Pulse leaf extracted to C11
  via Custard, compiled to `libfstar-codec.{dylib,so,a}` + `fstar_codec.h`,
  no karamel.

### `Data.Codec.Low` is PORTED to Pulse (this session)

The ~860-line Pulse rewrite is complete and 0-admit: 8 encoders + 8 decoders +
`encode_bytes`/`decode_bytes` dispatch + `varint_encode_pred`/
`varint_decode_expected` (`noextract` pure specs) + 8 roundtrip lemmas +
`lemma_low_encode_decode_match`.  Extracts to warning-free C11.  The port was
much easier than the proposal feared: the pure `codec` `.enc`/`.dec` are record
projections that compute, so `dec (enc x)` reduces and SMT discharges the
roundtrip lemmas automatically (the old `lemma_word32_shift_bytes` /
`FStar.HyperStack.ST.get ()` `h_mid` heap threading is GONE, not ported).

### Remaining work (NOT done)

- **T3.2 — the two test modules.**  `test/Data.Codec.Test.{Roundtrip,
  Integration}.fst` still `open` the dead Low*/`Stack` surface (`alloca`,
  `LB.upd`/`LB.index`) and reference the dropped helper lemmas
  (`lemma_pow2_32`, `lemma_buffer_length_bound`, `lemma_word32_shift_bytes`,
  `lemma_encode_varint_eq_buffer`, `lemma_decode_varint_roundtrip`, …).  They
  are still NOT in `TST_MODS`.  10 `Stack`-based tests in Roundtrip + ~20
  coverage anchors in Integration need a Pulse rewrite.
- The two test modules are the ONLY reason the gate runs `make check` with
  `SRC_MODS` only (no `TST_MODS`).

## The old KaRaMeL/Low\* layer is DEAD

F* `v2026.09.20` **removed the entire Low\*/KaRaMeL stdlib**: the namespaces
`FStar.HyperStack`, `FStar.HyperStack.ST`, and `LowStar.Buffer` no longer
exist.  Consequently:

- `src/Data.Codec.Low.fst` (the KaRaMeL `Stack`+`LowStar.Buffer` leaf) **cannot
  typecheck** against the new F\*.  It is still in the tree but not built.
- `test/Data.Codec.Test.{Roundtrip,Integration}.fst` both `open Data.Codec.Low`
  and are likewise not built.

The `krml` / `native` / `rust` / `wasm` targets were deleted along with the
KaRaMeL toolchain.  The only C-extraction path in the new F\* is **Custard**
(`--codegen Custard --custard_backend C`), and Custard extracts **Pulse**
(`fn`, `Pulse.Lib.Reference`/`Vec`/`Array`), not the old Low\* style.

## Roll-forward drift fixes (already landed, 0-admit preserved)

`src/Data.Codec.Types.fst` needed three upstream removals:

1. `open FStar.Mul` removed (module deleted; `*` is now natively multiplication).
2. `Prims.op_Multiply a 10` → `a * 10` (6 sites; `op_Multiply` deleted from `Prims`).
3. `--split_queries always` removed from two `#push-options` (option deleted;
   F* now emits one SMT query per proof obligation).

`default.nix` `ocaml` backend needed two fixes:

4. `--codegen OCaml` now requires **one source file per invocation** (Error 10).
5. OCaml extraction needs the dependencies' `.checked` files loaded — the
   `ocaml-src` derivation now verifies in dependency order (`--cache_checked_modules
   --cache_dir cache`) then extracts with `--include cache`.

flake.nix wiring (mirrors upstream `../fstar/flake.nix`):

- `ocamlPackages = ocaml-ng.ocamlPackages_5_3` (5.3, NOT 5.4 — `v2026.09.20`
  uses 5.3; 5.4 was only the fork's `t/ocaml-5.4` TopGit branch).
- `karamel` is **fully removed** — it is an in-tree git submodule of F\* that
  `.nix/fstar.nix` synthesizes only to install the `krml` binary + headers,
  which we do not consume.  The flake passes `karamel-src = emptyDirectory`
  + `karamelOcamlDeps = []` and sets `FSTAR_USE_KRML_EXE=1` with a no-op
  `karamel/Makefile` stub so the unconditional `make -C karamel install` is
  a NOP.  The installed F\* now ships only `fstar.exe` (no krml).
- The `fstar` derivation is overridden with
  `buildPhase = make OTHERFLAGS='--z3rlimit 20 --retry 3'` — the default
  rlimit (5) makes the 4-stage bootstrap's `FStar.Math.Fermat.binomial_theorem`
  deterministically time out (Error 19) under z3 4.13.3.  `OTHERFLAGS` flows
  into the nested `make -f mk/lib.mk` (the `.alib2.src.touch` recipe does not
  re-specify it, unlike `fsharp-lib.src`).

## Backend matrix (post roll-forward)

| Backend | Mechanism | Status |
|---|---|---|---|
| `ocaml` | `--codegen OCaml` (legacy ML) | ✅ GREEN now (pure spec; no Pulse needed) |
| `native` (C) | `--custard_backend C` (direct C11, no karamel) | ✅ GREEN (Pulse leaf ported) |
| `fsharp` | `--codegen FSharp` / `--custard_backend FSharp` | 🟡 same Pulse prerequisite (`.NET 10` SDK) |
| `rust` | `--custard_backend KrmlRust` → karamel | ❌ dead upstream (431 rustc errors, no `lowstar` module) |
| `wasm` | — | ❌ gone — no wasm backend in the new F\* |

Custard's `--custard_backend` enum is exactly `["OCaml"; "FSharp"; "KrmlC";
"KrmlRust"; "C"]`.  There is no wasm anywhere.  `native` is GREEN; `fsharp`
is a separate follow-up (`.NET 10`); `rust`/`wasm` are dropped permanently.

## Pulse idiom (pinned by the spike, applied to the leaf)

`spike/Data.Codec.Spike.fst` (gitignored) was the Phase-1 spike; the exact
idiom is now applied in `src/Data.Codec.Low.fst`.  Key facts:

- **Buffer type**: `A.array U8.t` (`Pulse.Lib.Array`), view `A.pts_to b s`
  (`s : Seq.seq U8.t` erased).  Read `b.(j)`, write `b.(j) <- x` with `j :
  SizeT.t`; convert `U32.t` offsets with `US.uint32_to_sizet`.
- **Public API stays `U32.t`** (matching the pure spec + OCaml extraction).
- **Bounds live in TYPES/refinements, not `pure` preconds** — a `pure (...)`
  fact in `requires` is NOT visible in the `ensures`; use `A.length b` (pure
  `Ghost nat`) for self-contained bounds and re-assert `A.length b ==
  Seq.length s` in the `pure`.
- **No `U32.v`/`U8.v`/nat `%` in extracted bodies** (Error 368): use
  `FStar.Int.Cast.uint32_to_uint8` / `uint8_to_uint32`.
- **`U32.add i k` needs `U32.v i + k < 4294967296`** in `requires`.
- **word32be/le use `U32.div` (not shift)** to match the pure `*.enc`
  division structure (avoids `lemma_word32_shift_bytes`).
- **`noextract`** on `varint_encode_pred`/`varint_decode_expected` keeps
  Custard from rooting them (they use `Seq`/`Prims.int`, which C can't emit).

## Definition of done

`nix build .#fstar-codec-checked` (0-admit, spec + leaf) and
`nix build .#fstar-codec-native` (C11 shared object, no karamel) are GREEN.
The two test modules (T3.2) are the only unfinished item.

## Build commands

```bash
nix build .#fstar-codec-checked   # verification gate (0-admit, spec + Pulse leaf)
nix build .#fstar-codec-ocaml     # OCaml package of the pure spec
nix build .#fstar-codec-native    # C11 shared/static lib of the Pulse leaf
nix develop && make check         # dev loop (no nix)
```
