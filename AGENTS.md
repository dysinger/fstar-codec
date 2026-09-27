# fstar-codec — Agent Guide & Handoff

`Data.Codec` — verified bidirectional codec library, extracted from the xeno
monorepo (`codec/`) as a standalone repo.  F* source is 0-admit; `checked` and
`krml` (`.krml` IR) extend GREEN.  This file records the session state and the
unfinished backend-extraction work so the next session resumes cleanly.

## Current state (Sep 27 session, second pass)

### GREEN (verified this session)

- `nix build .#fstar-codec-checked` — 0 admits (the gate; LSP is looser).
- `nix build .#fstar-codec-krml` — extracts ONLY `Data_Codec_Low.krml`.
- `nix build .#fstar-codec-native` — **NOW WORKS**.  Produces
  `libfstar-codec.dylib`/`.so` + `Data_Codec_Low.h`.
- `nix build .#fstar-codec-ocaml` — COMPILES (unchanged).
- Three-layer build architecture landed (matches the xeno
  `build-layer-separation` change).

### ROOT CAUSE FIXED (source surgery, 0-admit preserved)

The `FStar.List` reachability blamed in the previous handoff on
`open Data.Codec.Types` was actually two **top-level spec helpers** in
`Data.Codec.Low` itself — `open`'s spec symbols are erased, but these two
were being extracted:

- `varint_encode_pred : prop` — a pure predicate used only in `ensures`.
  FIXED with the bare `noextract` keyword on its own line before `let`.
  (`[@ noextract]` / `[@@ noextract]` are SYNTAX ERRORS in F* 2025.10.x.)
- `varint_decode_expected : Pure decode_result_c` — a pure spec helper, only
  consumed by `decode_varint`'s `ensures` + `Lemma` bodies.  FIXED by changing
  the effect `Pure` → `Ghost` (which prunes it from the `.krml`; `Pure` does
  not).

`strings Data_Codec_Low.krml | grep -cE 'varint_encode_pred|varint_decode_expected'`
now returns 0, and the generated C has ZERO `Prims_list`/`FStar_List`/`.tail`/
`.hd`/`TODO`/`PDeref` references.

### NOT done — `rust` and `wasm` are BLOCKED BY KaRaMeL backend defects

The root-cause fix unblocked `native`/C fully, and cleared the list error that
was masking two DEEPER KaRaMeL toolchain limitations (verified against the
KaRaMeL source in `../karamel/`):

- **wasm** — `AstToCFlat.ml` `size_of` maps a wasm value to a SINGLE
  `I32`/`I64`.  `decode_result_c` (a `DR_Inl of {code;pos} | DR_Inr of
  {n;value}` variant, 20 bytes/2 fields) is a flat struct and is UNRETURNABLE
  from a wasm function.  `-fnostruct-passing` and `-by-ref` do NOT fix it.
  The wasm backend has no multi-value struct returns.
- **rust** — `PrintMiniRust.ml:172` maps `Constant.CInt` (`krml_checked_int_t`,
  the mathematical-int type from `U32.v`/`U8.v`/`%`/`/`) to an EMPTY string, so
  `decode_varint`/`encode_varint` emit the invalid `let b4_val:  = …`.
  Additionally `-minimal` emits `crate::fstar`/`crate::prims`/
  `crate::lowstar::ignore` refs but KaRaMeL ships NO Rust runtime crate (unlike
  the C `libkrmllib.a`).

Both are real Low\* usage (mathematical ints + struct-returning decode API),
which the trivial template `Example.fst` never hits.  Detailed investigation +
fix recipes are recorded in the fstar-lowstar skill §15
(`~/.pi/agent/skills/fstar/fstar-lowstar/SKILL.md`).

**Next-session decision (needs OpenSpec gate — Mandate 15):** `rust`/`wasm`
require EITHER a KaRaMeL patch (`Constant.CInt -> "i64"` etc. + a Rust runtime
crate), OR an API refactor of `Data.Codec.Low`'s decode functions to return a
`U32.t` status and write `n`/`value`/`code`/`pos` via out-parameter pointers
(the classic C ABI, wasm-friendly).  Neither is ad-hoc source surgery.

## The `ocaml` target works (reference pattern)

`fstar.exe --codegen OCaml` emits underscored module files
(`Data_Codec_Types.ml`, `Data_Codec.ml` — dots become underscores).  The dune
`(modules ...)` stanza MUST use the underscored names, and the compiled OCaml
links against the fstar fork's shipped runtime `fstar.lib`
(`OCAMLPATH = "${fstar}/lib"`).  This already compiles to `.cmxa`.

## The native/rust/wasm failures (root-caused, not yet fixed)

Both failures share ONE root cause:

**`Data.Codec.Low` (src/Data.Codec.Low.fst:55) does `open Data.Codec.Types`.**
That `open` drags the pure, `list`-heavy `codec a` combinator layer
(`Data.Codec.Types` uses `FStar.List.Tot` everywhere: `list byte`,
`List.Tot.map`, `for_all`, `seq_of_list`, etc.) into the KaRaMeL extraction
closure.  The KaRaMeL rust/wasm backends cannot translate
`FStar.List.Tot.Base.hd` / `.tail` (structural list deconstruction →
`TODO: PDeref`), and emit `Fatal error: Unrecoverable error`.

`Data.Codec.Low` only actually needs from `Data.Codec.Types`:
- `byte`  = `U8.t`  (trivial type alias, Types:55)
- `byte_seq` = `Seq.seq byte`  (trivial alias, Types:58)
- `byte_val` (Types:940) — used ONLY in the ghost `ensures`/lemma spec portions
  of `encode_bytes`/`decode_bytes`, never in extractable code.

Specific failures observed:
- **native** — after adding `-warn-error -2 -9-16 -11 -26..28`, KaRaMeL emits C
  successfully (`Data_Codec_Low.c` + krmllib `C.*`) but the C link fails with
  `Prims_op_LessThan` / `Prims_op_Modulus` / etc. `undefined symbols` — the
  `libkrmllib.a` link step was added
  (`${karamel.home}/krmllib/dist/generic/libkrmllib.a`) but the `-drop`
  experiment below broke the extraction before reaching link.
- **rust** — `FStar.List.Tot.Base.hd__uint8_t ... TODO: PDeref` →
  `Fatal Not_found`.
- **wasm** — `FStar.List.Tot.Base.tail__uint8_t partially applied function` →
  `Unrecoverable error`.

## Next steps (in order)

1. **Re-scope via OpenSpec.**  This backend-extraction work is NOT yet an
   OpenSpec change.  Create one in the xeno monorepo (or a new `openspec/` here)
   titled e.g. `codec-native-rust-wasm` — it is F* source surgery + KaRaMeL
   tuning, so it needs proposal/design/tasks + the re-verify gate (Mandate 15).

2. **Narrow `open Data.Codec.Types` in `Data.Codec.Low`.**  Replace the `open`
   with local `byte`/`byte_seq` aliases and qualify (or inline) the ghost-
   spec `byte_val` usage.  This removes the `FStar.List` reachability that
   breaks rust/wasm.  **This is the real fix** — everything else is
   downstream of it.

3. **Re-verify 0-admit.**  `Data.Codec.Low` must still verify with zero admits
   after the narrowing (`nix build .#fstar-codec-checked` is the gate; LSP is
   looser).

4. **Then fix the backends with the known-good KaRaMeL flags** (from
   `tls/Makefile` in the monorepo — the canonical reference):
   - `-warn-error -2 -warn-error -9-16 -warn-error -11 -warn-error -26..28`
   - `-no-prefix 'Data.Codec.*'`
   - native link: compile all emitted `.c` to `.o`, link
     `${karamel.home}/krmllib/dist/generic/libkrmllib.a` (for `Prims_*` symbols).

## Things to try next session (if step 2 alone doesn't clear rust/wasm)

- **`-drop` uses `.krml` basenames (underscored), one per arg or comma-
  separated** — NOT dotted module names, NOT space-joined.  Earlier `-drop
  Data_Codec_Types Data_Codec ...` failed with "Unknown file extension for
  Data_Codec" because space-joining was mis-parsed.  Correct form is
  `-drop Data_Codec_Types,Data_Codec,FStar_List_Tot_Base,FStar_List_Tot` (or
  one `-drop` per name).
- **Do not pass all 3515 `${fstar-krml}/krml/*.krml`** into the rust/wasm
  backends — that bundle includes `FStar_List_Tot_Base.krml` and forces the
  list reachability.  Pass only the runtime `.krml` `Data.Codec.Low` actually
  references (`FStar_UInt8`, `FStar_UInt32`, `FStar_Seq_Base`, `Prims`,
  `LowStar_Buffer`, `FStar_HyperStack`, `C_*`, `Lib_*`).
- **`-bundle 'Data.Codec.Low=FStar.List.Tot.Base,FStar.List.Tot'`** (API/impl
  split) as an alternative reachability-scoping to `-drop`, per
  fstar-lowstar §12.
- **`-add-include '"krml/internal/compat.h"'`** for the Warning 15 non-Low\*
  math (`Prims.op_LessThan`, etc.) if the C link still reports them unresolved
  after `libkrmllib.a` is linked.

## Key facts (do not re-derive)

- `Data_Codec_Low.krml` itself has ZERO `FStar.List` references — the list
  reachability comes ONLY from `open Data.Codec.Types` in the `.fst` source,
  not from the `.Low` body.
- The fstar fork already ships the full OCaml runtime (`lib/fstar/lib/` =
  `fstar.lib`, `fStar_UInt8.cmx`, `fStar_List_Tot_Base.cmx`, ...).  The xeno
  monorepo's repo-local `ulib/` (hand-written `.ml` stubs) is a REDUNDANT
  vendored duplicate — do not cargo-cult it into this repo.  Link against
  `fstar.lib` via `OCAMLPATH = "${fstar}/lib"` (already done for `ocaml`).
- `nix/karamel-*.patch` in xeno patch KaRaMeL's OCaml source (`lib/Ast.ml`,
  `lib/Checker.ml`, `lib/Simplify.ml`), NOT F*'s ulib, and appear UNAPPLIED by
  xeno's nix build.  They do not belong here; do not copy them.
- The template's example works for native/wasm/rust because `Example.fst` uses
  no `uint_to_t`/`U32.v`/list ops — do NOT copy the template's bare
  `native`/`wasm`/`rust` derivation verbatim onto a real Low* module; they need
  the krmllib link + warn-erorr flags.

## Build commands

```bash
nix build .#fstar-codec-checked   # verification gate (0-admit)
nix build .#fstar-codec-krml      # extract Data_Codec_Low.krml
nix build .#fstar-codec-ocaml     # WORKS
nix build .#fstar-codec-native    # BROKEN (unfinished)
nix build .#fstar-codec-rust      # BROKEN (unfinished)
nix build .#fstar-codec-wasm      # BROKEN (unfinished)
nix develop && make check && make krml   # dev loop (no nix)
```
