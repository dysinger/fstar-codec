# fstar-codec — Agent Guide & Handoff

`Data.Codec` — verified bidirectional codec library, extracted from the xeno
monorepo (`codec/`) as a standalone repo.  F* source is 0-admit.  This file
records session state and the unfinished Pulse-port work so the next session
resumes cleanly.

## Current state (roll-forward session)

### GREEN (verified this session, F* `v2026.09.20+lsp`)

- `nix build .#fstar-codec-checked` — 0 admits.  Verifies the **pure spec**
  modules only: `Data.Codec.Types` + `Data.Codec`.
- `nix build .#fstar-codec-ocaml` — compiles the pure spec to an OCaml
  findlib package (`fstar_codec`), linking against `fstar.lib`.

### The old KaRaMeL/Low\* layer is DEAD

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
| `native` (C) | `--custard_backend C` (direct C11, no karamel) | 🟡 needs the Pulse leaf |
| `fsharp` | `--codegen FSharp` / `--custard_backend FSharp` | 🟡 same Pulse prerequisite (`.NET 10` SDK) |
| `rust` | `--custard_backend KrmlRust` → karamel | ❌ dead upstream (431 rustc errors, no `lowstar` module) |
| `wasm` | — | ❌ gone — no wasm backend in the new F\* |

Custard's `--custard_backend` enum is exactly `["OCaml"; "FSharp"; "KrmlC";
"KrmlRust"; "C"]`.  There is no wasm anywhere.  `native` and `fsharp` both
land once the leaf is Pulse; `rust`/`wasm` are dropped permanently.

## Next step — AGENDA: rewrite `Data.Codec.Low` in Pulse

The single C leaf (`Data.Codec.Low`, ~1100 lines) must be rewritten from the
KaRaMeL `Stack`+`LowStar.Buffer` style to **Pulse** so it can extract via
Custard (`--custard_backend C`).  This IS the next session's primary task.
The pure spec (`Data.Codec.Types` / `Data.Codec`) stays exactly as-is.

### Key facts for the port

- Custard's buffer rules (`src/custard/FStarC.Custard.Builtins.fst`
  `pulse_rule`) cover ONLY `Pulse.Lib.Reference`, `Pulse.Lib.Vec`,
  `Pulse.Lib.Array.Core`, `Pulse.Lib.Box`, `Pulse.Lib.ArrayPtr`.  There is no
  `LowStar.Buffer` rule.
- Custard requires `--custard_monomorphize_types true` for the C backend (no
  type variables in C).
- `decode_result_c` (a tagged union) returns fine from Custard-C (unlike the
  old KaRaMeL wasm backend) — the C backend emits an if/else chain, not a
  struct-return trap.
- The Kaplan reference: `../fstar/doc/ref/custard.md` §7.4 (Pulse → IR rule
  table), §3.1 (monomorphization), §16 (test matrix), §4.4 (entry points).
- Pulse examples to crib from: `../fstar/pulse/lib/pulse/lib/Pulse.Lib.Array.Core.fst`
  and the Custard C regression `tests/custard/KrmlBasic.fst` (records, variants,
  machine integers).

### Port plan (in dependency order)

1. **Map the API surface.**  The 8 leaf encoders/decoders + `encode_bytes`/
   `decode_bytes` + the `codec_t`/`decode_result_c` types all carry over.  The
   `Stack` effect becomes Pulse `fn`; `LB.buffer U8.t` becomes a `Pulse.Lib.Vec.vec
   U8.t` (or `Array` for stack-allocated); `LB.upd`/`LB.index` become
   `Pulse.Lib.Vec`'s read/write; `modifies (LB.loc_buffer b)` / `h0 == h1` become
   Pulse separation-logic pre/post.
2. **Start with the simplest leaf** (`encode_token` / `decode_token`) as a
   spike to pin the correct Pulse idiom, then replicate across the other 7.
3. **`decode_result_c` is a plain tagged union → fine for C.**  No out-param
   refactor needed (that was the OLD wasm limitation; Custard-C has no such
   constraint).
4. **Re-verify 0-admit** — `nix build .#fstar-codec-checked` after re-adding
   the leaf + its two test modules to `SRC_MODS`/`TST_MODS`.  The two test
   modules will also need their `Low` references updated to the Pulse surface.
5. **Wire the `native` target** — `fstar.exe --codegen Custard --custard_backend C
   --custard_monomorphize_types true --custard_entry_module Data.Codec.Low`
   (whole-program from an entry; a library has no `main`, so use
   `--custard_entry_module`, not `--custard_main`).
6. **Optionally land `fsharp`** (`.NET 10` SDK + `--custard_backend FSharp`).

### Definition of done

`nix build .#fstar-codec-checked` (0-admit, spec + leaf + tests) and
`nix build .#fstar-codec-native` (C11 shared object from Custard, no karamel)
GREEN.

## Build commands

```bash
nix build .#fstar-codec-checked   # verification gate (0-admit, pure spec only)
nix build .#fstar-codec-ocaml     # OCaml package of the pure spec
nix develop && make check         # dev loop (no nix)
```
