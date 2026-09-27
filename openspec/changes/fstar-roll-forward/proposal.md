# Change Proposal: fstar-roll-forward

## Summary

Roll the `fstar-codec` nix build forward from the pinned `dysinger/fstar`
`v2025.10.06+lsp` to F* `v2026.09.20` (the first stable tag that ships the new
"Custard" whole-program extractor), and re-verify the whole package against it.

## Motivation

`fstar-codec` currently pins a fork (`github:dysinger/fstar/v2025.10.06+lsp`)
built on a ~10-month-old F* base.  Research (`../fstar`, `../karamel`, both
freshly remote-updated) showed the two backend blockers that keep `rust`/`wasm`
non-GREEN are **KaRaMeL backend defects**, not `fstar-codec` source bugs, and
they are still present at the latest `karamel` `upstream/master`:

- **Rust** — `karamel/lib/PrintMiniRust.ml` maps `Constant.CInt`
  (`krml_checked_int_t`, the mathematical-int type produced by `U32.v`/`U8.v`/
  `%`/`/`) to an empty string, and references a `crate::lowstar` module that is
  never emitted.  Upstream `FINDINGS.md` #10 and #5–7 document these and state
  plainly *"the Rust backend refuses mathematical integers outright."*
- **wasm** — `karamel/lib/AstToCFlat.ml` `size_of` maps a wasm value to a single
  `I32`/`I64`; a flat struct/tagged-union return type (`decode_result_c`) is
  `failwith "size_of: this case should've been eliminated"`.  No wasm
  multi-value struct-return support exists in any branch.

The path forward is not to fix those backends (they are broken upstream, and
`rust`/`wasm` are not currently GREEN anyway) but to adopt F*'s **new native
extractor, "Custard"** (`doc/ref/custard.md`, `src/custard/`), which:

- is **demand-driven** — ghost/lemma/`noextract` code is never even looked at,
  removing the whole reachability class of bug this package just worked around;
- has a **direct-C** backend (`--custard_backend C`) that monomorphizes
  mathematical integers correctly instead of routing them through krmllib's
  truncated `int32_t krml_checked_int_t`.

Custard first appears in a stable tag at **`v2026.09.20`** (443 files; the tags
`v2026.05.03` and `v2026.08.30` have zero Custard files).  It is experimental
("a design sketch, not a shipped specification"), so this change is an explicit
**opt-in roll-forward probe**, not a claim that Custard is production-ready.

## Scope

- **In scope**:
  - Point `flake.nix`'s `fstar` input at `v2026.09.20` (see Design for the
    fork-vs-upstream question), update the `flake.lock`, and make any nix
    derivation fixes the new toolchain needs.
  - Re-verify `nix build .#fstar-codec-checked` (the 0-admit gate) and
    `.#fstar-codec-krml`/`.#fstar-codec-native`/`.#fstar-codec-ocaml` against
    the new F*.
  - Probe Custard (`--codegen Custard --custard_backend C`) as a candidate
    replacement for the `native` C path, and record what works vs. what does
    not.
- **Out of scope**:
  - Fixing the KaRaMeL `rust`/`wasm` backends (broken upstream; not our code).
  - Landing a `rust` or `wasm` target (Custard's Rust backend is *unimplemented*
    — `FStarC.Custard.Driver.fst` "not implemented for `--custard_backend
    KrmlRust`" — and Custard has no wasm backend at all).  These are dropped as
    near-term goals, not deferred work.
  - The xeno monorepo (this change is scoped to the `fstar-codec` standalone
    repo; a monorepo roll-forward is a separate, larger change).

## Risks

- `v2026.09.20` may need a matching `karamel` and `ocamlPackages` bump; the nix
  overlay in `flake.nix` (`fstar.nix`, `karamel.nix`, `z3.nix`) may drift.
- **LSP regression is the main risk.**  Upstream `FStarLang/FStar` has NO LSP
  server, and the `dysinger/fstar` fork only carries it as `+lsp` tags
  (latest: `v2025.12.15+lsp`).  Rolling to plain `v2026.09.20` silently drops
  `fstar.exe --lsp`.  **Resolved**: a fork branch `v2026.09.20+lsp` was created
  in `../fstar` (commit `cf847952b9`) that rebases the LSP server onto
  `v2026.09.20` — the flake's `fstar` input points at that branch, not the
  bare upstream tag.
- Custard is experimental: direct-C output may not yet cover `Data.Codec.Low`'s
  constructs (buffers, `Stack`, sum types), and its `KrmlRust` backend is
  explicitly unimplemented.
- 0-admit status must be re-proven under the new F* (the LSP/tools check is
  looser than `nix build .#fstar-codec-checked`, per Mandate 20).
- The `v2026.09.20+lsp` port was audited statically (every API the LSP modules
  reach was verified present + signature-compatible), but the 4-stage compiler
  bootstrap has NOT yet been run — the build may surface drift the static audit
  missed.

## Dependencies

- `codec-native-rust-wasm` (this session's root-cause fix and `native` landing,
  still uncommitted/archived) — the `noextract`/`Ghost` pruning and minimal
  runtime set carry forward.
- `../fstar` branch `v2026.09.20+lsp` (the LSP port, this session).
