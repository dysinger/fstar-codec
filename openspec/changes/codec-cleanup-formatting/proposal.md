# Change Proposal: codec-cleanup-formatting

## Summary

Clean up the repo's source organization, documentation, and formatting: group
and sort `Data.Codec.Pulse` declarations, add fsdoc to every declaration,
bring the README build instructions up to date, format the nix code, and add a
`treefmt` / `treefmt.nix` formatter entry for every file type in the repo
(including a F\* formatter driven through `fstar.exe --ide format`).

## Motivation

The Custard backend work (previous changes) landed `native`/`ocaml`/`fsharp`
targets and left the repo in a working but unpolished state:

- `Data.Codec.Pulse` declaration order is ad hoc (encoders/decoders are not
  alphabetically grouped; `encode_varint` and the `varint_encode_pred` spec
  helper sit out of order mid-file).
- Not every `fn`/`let`/`type` carries fsdoc.
- `README.md` is stale: it says the default package is `fstar-codec-checked`,
  omits `fstar-codec-native` and `fstar-codec-fsharp`, calls the Pulse leaf
  "pending", and says Custard's C backend is the only one (OCaml + F# now
  exist too).
- The nix code (`flake.nix`, `default.nix`) is hand-indented and has no
  formatter config.
- There is no `treefmt.nix` / `treefmt.toml` to enforce formatting across the
  repo's file types.

## Scope

- In scope:
  - Re-group `Data.Codec.Pulse` declarations: types together, encoders together
    (alphabetical), decoders together (alphabetical), spec helpers with their
    subject, lemmas together (alphabetical).
  - Add fsdoc (`(** ... *)`) to every `type`, `let`, and `fn` in
    `Data.Codec.Pulse` (and audit `Data.Codec.Types` / `Data.Codec` for gaps).
  - Update `README.md` build instructions to the four current targets and the
    current default.
  - Format `flake.nix` + `default.nix` with a nix formatter.
  - Add `treefmt.nix` (or `treefmt.toml`) wiring formatters for every file type:
    `*.fst`/`*.fsti` (F\*), `*.nix` (nixfmt), `*.md` (as applicable), etc.
- Out of scope: behavioral changes to the codec, new backends, the F# follow-up.

## Definition of done

- `Data.Codec.Pulse` declarations are grouped + sorted, with fsdoc on every
  declaration, and still verify at 0-admit.
- `README.md` documents `nix build` for `fstar-codec-checked`,
  `fstar-codec-ocaml`, `fstar-codec-native`, `fstar-codec-fsharp`, and the
  `devShell`/`make check` dev loop, with the correct default.
- `nix fmt` (or the chosen treefmt entry point) formats the nix + F\* source
  with no remaining diff.
- `treefmt.nix` covers every file type and is wired into the flake check.
