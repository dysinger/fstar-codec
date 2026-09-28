# Change Proposal: pulse-fsdoc-finalize

## Summary

Finish the cleanup work left half-done at the end of the previous session:
group/sort + fsdoc the `Data.Codec.Pulse` module, fsdoc-audit the pure spec
modules, and run the *real* nix build gate (not just the direct `fstar.exe`
verify driver).

## Motivation

The previous session (the `codec-cleanup-formatting` change) landed the
functional test-rewrite work (Pulse test port, 100% lemma coverage) plus README
+nix+treefmt, but **T1 (regroup + fsdoc) and T5.2 (real `nix build`) were never
touched**.  Those are the literal "cleanup and formatting" core the change was
named for, and they must land before the repo is "perfected".

## Scope

- In scope: regroup/fsdoc `Data.Codec.Pulse`; fsdoc-audit `Data.Codec.Types` +
  `Data.Codec`; run the real `nix build .#native .#ocaml .#fsharp` + `nix flake
  check` gate; verify 0-admit.
- Out of scope: new backends, behavioral changes, the F# `.NET 10` follow-up,
  any F\* formatter (broken upstream — see `codec-cleanup-formatting` T4.3).

## Definition of done

- `Data.Codec.Pulse` declarations grouped + sorted (types / encoders / decoders /
  dispatchers / lemmas), every `type`/`fn`/`let` fsdoc'd, still 0-admit.
- `nix build .#native .#ocaml .#fsharp` and `nix flake check` (incl. the new
  `.#formatting` target) all succeed.
