# Implementation Tasks: fstar-roll-forward

**Change**: roll the `fstar-codec` toolchain from `dysinger/fstar`
`v2025.10.06+lsp` to `v2026.09.20` (first stable tag with the Custard
extractor), keeping the fork's LSP server by porting it onto a new
`v2026.09.20+lsp` branch.

## Phase 0 — Port the LSP onto v2026.09.20 (fork work) — DONE this session

The LSP server exists only in the `dysinger/fstar` fork (maintained on `t/lsp`,
last tagged `v2025.12.15+lsp`); upstream `FStarLang/FStar` has none.  Rolling to
`v2026.09.20` without porting would silently drop `fstar.exe --lsp`.

- [x] **T0.1 — Create the branch.**  `../fstar`, branch `v2026.09.20+lsp` off
      `v2026.09.20` (fork tag == upstream `FStarLang/FStar` 0757e0890).
- [x] **T0.2 — Port `src/lsp/*`.**  Eight new files
      (`FStarC.LSP.{Messages,Server,Translator,Transport}.{fst,fsti}`) taken
      verbatim from `origin/t/lsp`.  Static audit confirmed every API they
      reach is present + signature-compatible on `v2026.09.20`
      (`repl_state`, `query'`/`FullBuffer`/`Full`, `AutoComplete`/`CKCode`,
      `Lookup`/`LKSymbolOnly`/`LKCode`, `issue`/`issue_level`, `format_issue'`,
      `Range.Ops` `start_of_use_range`/`end_of_use_range`/`line_of_pos`/
      `col_of_pos`).
- [x] **T0.3 — Port the wiring.**  `--lsp` CLI option + `get_lsp`/`lsp`
      (Options), `Error_FlagConflict`/`Error_LSPError` (Errors.Codes),
      `open_null_reader` (Util.fsti + ml/FStarC_Util.ml), `lsp` dir added to
      `src/fstar.include`, `js_repl_eval`/`install_ide_mode_hooks` exported from
      `Interactive.Ide.fsti` (impls already merged upstream), capture printer
      set/clear + `write_json` routing (JsonHelper), `--lsp` entry point in
      `Main.fst` (mutually exclusive with `--ide`), `tc_one_fragment` uses
      `ide_filename` (Universal.fst).  Error codes re-numbered 396/397 (the
      base had advanced to 395 with Custard errors).
- [x] **T0.4 — Commit** `cf847952b9` on `v2026.09.20+lsp`.  (Push failed:
      SSH publickey denied; leave for the session where the right remote
      credential is available.)

- [ ] **T0.5 — Defer the operator-lookup enhancement.**  The t/lsp
      `Syntax.DsEnv` "`op_` → display-name" resolution (for operator
      hover/completion) was NOT ported — `v2026.09.20` refactored
      `find_in_module_with_includes` into a `_gen` form, so this needs careful
      re-integration.  Non-blocking for the LSP server to build/run.

## Phase 1 — Build + verify the forked compiler

- [ ] **T1.1 — Bootstrap `v2026.09.20+lsp`.**  `../fstar`, `make -j` (4-stage:
      stage0 → stage1 verify → stage2 extract → stage3).  Fix any F*/OCaml
      drift the static audit missed.  Gate: a `stage3/out/bin/fstar.exe` that
      accepts `--lsp`.
- [ ] **T1.2 — Smoke-test LSP.**  `fstar.exe --lsp` starts and speaks LSP
      (`initialize` → `initialized` handshake) without the `repl_stdin`/IDE
      interleaving regressions the t/lsp branch fixed.
- [ ] **T1.3 — Push the branch.**  With working credentials (HTTPS token or
      key), `git push -u origin v2026.09.20+lsp`.

## Phase 2 — Point fstar-codec at the new toolchain — DONE

> Landed this session.  karamel is **fully removed**: it is an in-tree git
> submodule of F\* that `.nix/fstar.nix` synthesizes only to install `krml`,
> which we don't use.  The flake passes `karamel-src = emptyDirectory` +
> `karamelOcamlDeps = []` and neutralizes the `make -C karamel install` step
> via `FSTAR_USE_KRML_EXE=1`.  No fork needed.

- [x] **T2.1 — flake.nix: `fstar.url`.**  → `github:dysinger/fstar/v2026.09.20+lsp`.
- [x] **T2.2 — OCaml version: 5.3.**  `ocamlPackages_5_3` everywhere (5.4 was
      the fork's `t/ocaml-5.4` TopGit branch, not the tag).
- [x] **T2.3 — karamel input.**  Removed entirely (see note above).
- [x] **T2.4 — flake.lock.**  Updated (fstar → `cf84795`, karamel removed).
- [x] **T2.5 — Re-verify the gate.**  `nix build .#fstar-codec-checked` GREEN
      at 0 admits + `.#fstar-codec-ocaml` GREEN.  (`krml`/`native` removed —
      F\* v2026.09.20 deleted the Low\*/KaRaMeL stdlib, so those targets are
      gone, not merely broken.)

  The bootstrap needed `OTHERFLAGS='--z3rlimit 20 --retry 3'` (see flake.nix
  `fstar` override) — default rlimit 5 makes `FStar.Math.Fermat.binomial_theorem`
  deterministically time out.

  Source drift fixed: `open FStar.Mul` removed, `Prims.op_Multiply` → `*`,
  `--split_queries always` removed.

## Phase 3 — Custard: the leaf needs a Pulse port, not a probe

> **Finding (this session):** the `Data.Codec.Low` leaf is KaRaMeL Low\*
> (`Stack` + `LowStar.Buffer`), and F\* `v2026.09.20` **removed that entire
> stdlib**.  Custard's C backend extracts **Pulse** (`Pulse.Lib.Reference`/
> `Vec`/`Array`), not Low\*.  So `--codegen Custard --custard_backend C` on
> the current leaf is a non-starter; the leaf must be ported to Pulse first.

- [x] **T3.1 — Probe.**  Not applicable until the leaf is Pulse.  The pure
      spec (`Types`/`Codec`) extracts fine via OCaml; the leaf does not yet.
- [ ] **T3.2 / T3.3.**  Deferred to the Pulse-port change.

## Phase 4 — Decide rust/wasm fate + commit

- [x] **T4.1 — Record the verdict.**  `rust`/`wasm` (and the whole KaRaMeL
      `krml`/`native` layer) are dropped — the toolchain that produced them
      was deleted upstream.  The only C path is Custard, gated on the Pulse
      port of `Data.Codec.Low`.  Documented in README + AGENTS.md.
- [ ] **T4.2 — Commit.**  Pending review.

## Definition of done

`nix build .#fstar-codec-checked` (0-admit) + `.#fstar-codec-ocaml` GREEN
against `v2026.09.20+lsp`; KaRaMeL/Low\* layer confirmed dead upstream and
removed; Custard-C gated on a Pulse port of `Data.Codec.Low` (next change).
