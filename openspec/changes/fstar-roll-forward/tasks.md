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

## Phase 2 — Point fstar-codec at the new toolchain

- [ ] **T2.1 — flake.nix.**  Change `fstar.url` to the fork branch
      (`github:dysinger/fstar/v2026.09.20+lsp`).  Decide whether `karamel` and
      the nix overlay (`fstar.nix`, `karamel.nix`, `z3.nix`) need matching
      bumps; `v2026.09.20`'s `.nix/fstar.nix`/`flake.nix` drifted from the
      current pin (96/59-line diffs) — review before adopting.
- [ ] **T2.2 — flake.lock.**  `nix flake update --update-input fstar` (and any
      karamel/ocamlPackages bumps).
- [ ] **T2.3 — Re-verify the gate.**  `nix build .#fstar-codec-checked` GREEN
      at 0 admits (NOT the LSP check — looser), then
      `.#fstar-codec-krml`/`.#fstar-codec-native`/`.#fstar-codec-ocaml`.

## Phase 3 — Probe Custard (the point of the roll-forward)

- [ ] **T3.1 — `--codegen Custard --custard_backend C`** on `Data.Codec.Low`
      (via `--custard_entry`), compare against the existing `native` (krml→C)
      output.  Record which constructs Custard covers (buffers? `Stack`? the
      `decode_result_c` tagged union?) and which fall out.
- [ ] **T3.2 — `--custard_monomorphize_types`** for the mathematical-int cases
      (varint `%`/`/`) that krmllib truncates to `int32_t`.
- [ ] **T3.3 — `--custard_backend KrmlRust`.**  Expected to be explicitly
      unimplemented (`FStarC.Custard.Driver.fst`); record the exact message and
      note it as a future datapoint, not a blocker.

## Phase 4 — Decide rust/wasm fate + commit

- [ ] **T4.1 — Record the verdict.**  Confirm `rust`/`wasm` remain non-GREEN
      (KaRaMeL backend defects; Custard has no wasm, and its Rust is
      unimplemented) and document them as explicitly dropped near-term goals in
      the README (update the target table).
- [ ] **T4.2 — Commit** the flake/default/source changes in `fstar-codec`
      (NOT `AGENTS.md`), and archive the `codec-native-rust-wasm` change after
      this lands.

## Definition of done

`nix build .#fstar-codec-checked` (0-admit) + `.#fstar-codec-native` (C) +
`.#fstar-codec-ocaml` GREEN against `v2026.09.20+lsp`; Custard direct-C probed
and findings recorded; `rust`/`wasm` documented as dropped (not deferred);
fork branch pushed.
