# Implementation Tasks: codec-cleanup-formatting

**Change**: group/sort `Data.Codec.Pulse` declarations, add fsdoc everywhere,
refresh README build docs, format nix, add `treefmt`/`treefmt.nix` for every
file type.

> ⚠️ **MANDATE:** every `fstar.exe` / `nix build` / `make` invocation is wrapped
> in a hard timeout (a `(sleep N && kill -9 $pid) &` guard).  Re-verify (0-admit)
> after *every* source reordering — a moved `fn`/`let` must not break its proofs.

## Phase 1 — Re-group + fsdoc `Data.Codec.Pulse`

- [ ] **T1.1 — Types block.**  Keep the five types (`codec_t`, `error_code_c`,
      `decode_error_c`, `decode_result_ok`, `decode_result_c`) contiguous, each
      with full fsdoc.
- [ ] **T1.2 — Encode functions, alphabetical.**  Order the eight encoders
      `encode_byteval`, `encode_token`, `encode_uint8`, `encode_varint`,
      `encode_word16be`, `encode_word16le`, `encode_word32be`, `encode_word32le`
      (alphabetical), each with fsdoc.  Move `varint_encode_pred` (the spec
      helper) to sit immediately above `encode_varint`, not mid-file.
- [ ] **T1.3 — Decode functions, alphabetical.**  Order the eight decoders
      `decode_byteval`, `decode_token`, `decode_uint8`, `decode_varint`,
      `decode_word16be`, `decode_word16le`, `decode_word32be`, `decode_word32le`
      (alphabetical), each with fsdoc.  Move `varint_decode_expected` to sit
      immediately above `decode_varint`.
- [ ] **T1.4 — Dispatchers.**  `encode_bytes` then `decode_bytes`, each with
      fsdoc.
- [ ] **T1.5 — Lemmas block.**  Order the roundtrip lemmas alphabetically
      (`..._byteval`, `..._token`, `..._uint8`, `..._varint`, `..._word16be`,
      `..._word16le`, `..._word32be`, `..._word32le`) then
      `lemma_varint_roundtrip_smtpat` + `lemma_pulse_encode_decode_match`, all
      with fsdoc.
- [ ] **T1.6 — Audit fsdoc on `Data.Codec.Types` + `Data.Codec`.**  Fill any
      missing fsdoc comments (at minimum: every public `type`, `let codec`,
      `let` combinator, and `Lemma`).

## Phase 2 — README

- [ ] **T2.1 — Rewrite "Getting started".**  Document:
      `nix build` (default = `fstar-codec-native`), the four targets
      (`checked`, `ocaml`, `native`, `fsharp`), and `nix develop && make check`.
- [ ] **T2.2 — Refresh "Modules" + "Architecture".**  Remove "pending Pulse
      port"; list the three source modules + two test modules accurately; note
      the Custard backends (`C`, `OCaml`, `FSharp`) that produce the binaries.

## Phase 3 — Format nix

- [ ] **T3.1 — Pick + apply a nix formatter.**  `nixpkgs-fmt` or `alejandra` on
      `flake.nix` + `default.nix`; confirm `nix flake show`/`nix build` still
      succeed after formatting.

## Phase 4 — treefmt

> **NOTE — canonical template:** `../xeno/treefmt.nix` is the sibling project
> (`..` is `~/`; `xeno` is the F\* monorepo this repo was extracted from), so its
> `treefmt.nix` (minimal `_: { … }` module, `programs.*.enable`, shared excludes)
> is the closest match and the template to port.  `../brainz`, `../db`,
> `../recon` follow the same convention.
>
> **File types in THIS repo** (to enumerate formatters over): `*.fst`/`*.fsti`
> (5 files), `*.nix` (2: `flake.nix` + `default.nix`), `*.md` (16).  No `*.sh`,
> no `*.json` (other than `flake.lock`).  So the formatter set is **fstar +
> nixfmt + prettier(md)** — plus `deadnix`/`statix` only if they cover this repo's
> small nix surface (they are enabled in `../xeno`).

Follow the **existing `treefmt.nix` convention** used across sibling projects
(`../xeno/treefmt.nix`, `../brainz/treefmt.nix`, `../db/treefmt.nix`,
`../recon/treefmt.nix`): declarative `programs.<formatter>.enable = true`,
`projectRootFile = "flake.nix"`, a shared `settings.excludes` list, and
`settings.includeExcludes = true`.  Match those, adding formatters for every
file type present in *this* repo.

- [ ] **T4.1 — Add `treefmt.nix`** in the sibling-repo style (module form
      `{ pkgs, lib, ... }:`, `projectRootFile = "flake.nix"`).
- [ ] **T4.2 — nix formatters** (`programs.nixfmt.enable = true`;
      `programs.deadnix.enable = true`; `programs.statix.enable = true`) — as
      in `../xeno`.
- [ ] **T4.3 — F\* formatter** wired as specced: a `fstar-fmt` shell application
      that drives `fstar.exe --ide` with a `format` query (see the snippet
      below — `includes = ["*.fst" "*.fsti"]`;
      `excludes = [".cache*" "_output/*"]`).  This is the ONE custom formatter
      (F\* is not a built-in treefmt-nix `programs.*` entry), so it uses
      `settings.formatter.fstar` as in the snippet.
- [ ] **T4.4 — Markdown/JSON/etc.** formatter entry where present (prettier for
      `*.md`/`*.json`, matching sibling `prettier` settings).
- [ ] **T4.5 — Wire `treefmt` into the flake check** (a `treefmt` check target).

## Phase 5 — Re-verify

- [ ] **T5.1 — `nix build .#fstar-codec-checked`** green, 0-admit (after the
      re-group).
- [ ] **T5.2 — `nix build .#fstar-codec-native .#fstar-codec-ocaml
      .#fstar-codec-fsharp`** green.

---

### Reference: F\* formatter for `treefmt.nix`

```nix
{ pkgs, lib, ... }:
let
  fstar-fmt = pkgs.writeShellApplication {
    name = "fstar-fmt";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      set -euo pipefail
      fstar="''${FSTAR_EXE:-${lib.getExe pkgs.fstar}}"

      fmt_one() {
        local file="$1"
        local code
        code=$(cat -- "$file")
        python3 - "$fstar" "$file" "$code" <<'PY'
      import json, os, subprocess, sys
      fstar, path, code = sys.argv[1], sys.argv[2], sys.argv[3]
      extra = os.environ.get("FSTAR_FMT_FLAGS", "").split()
      proc = subprocess.Popen(
          [fstar, "--ide", *extra, path],
          stdin=subprocess.PIPE,
          stdout=subprocess.PIPE,
          stderr=subprocess.PIPE,
          text=True,
      )
      info = proc.stdout.readline()
      if not info:
          sys.stderr.write(f"fstar --ide produced no protocol-info for {path}\n")
          sys.stderr.write(proc.stderr.read())
          sys.exit(1)
      proc.stdin.write(json.dumps({
          "query-id": "1",
          "query": "format",
          "args": {"code": code},
      }) + "\n")
      proc.stdin.flush()
      formatted = None
      status = "failure"
      while True:
          line = proc.stdout.readline()
          if not line:
              break
          try:
              msg = json.loads(line)
          except json.JSONDecodeError:
              continue
          if msg.get("kind") != "response" or str(msg.get("query-id")) != "1":
              continue
          status = msg.get("status", "failure")
          resp = msg.get("response")
          if isinstance(resp, str):
              formatted = resp
          elif isinstance(resp, dict):
              formatted = (
                  resp.get("formatted-code")
                  or resp.get("code")
                  or resp.get("formatted")
              )
          break
      try:
          proc.stdin.write(json.dumps({
              "query-id": "2",
              "query": "exit",
              "args": {},
          }) + "\n")
          proc.stdin.close()
      except BrokenPipeError:
          pass
      proc.wait()
      if status != "success" or not isinstance(formatted, str):
          sys.stderr.write(f"fstar format failed: {path} status={status}\n")
          sys.stderr.write(proc.stderr.read() if proc.stderr else "")
          sys.exit(1)
      if formatted != code:
          open(path, "w", encoding="utf-8", newline="\n").write(formatted)
      PY
      }

      for file in "$@"; do
        fmt_one "$file"
      done
    '';
  };
in
{
  projectRootFile = "flake.nix";

  settings.formatter.fstar = {
    command = "${fstar-fmt}/bin/fstar-fmt";
    includes = [ "*.fst" "*.fsti" ];
    excludes = [
      ".cache*"
      "_output/*"
    ];
  };
}
```
