# Change Proposal: reviewer-findings

## Summary

Land every finding from the uncompromising code review as actionable tasks.
The review found the code largely coherent and the Pulse port real work, but
the **prose layer** is systematically out of sync with the source: the
"zero admits" claim is contradicted by a scoped `--admit_smt_queries true` in
a shipped test module; the combinator count is asserted at 19/21/22 in three
places; the README advertises ~9 combinators/operators that don't exist; test
and line counts are off by one; dead types and hand-duplicated spec/impl pairs
survive the claimed cleanup; and the `.NET 10` + fork-tag claims are not
reproducible from the committed files.

## Motivation

The repository's credibility value proposition is "verified, 0-admit".  When a
fresh reader can grep the shipped source and find `admit_smt_queries` on, or
follow the README's combinator list to nothing, every number the repo asserts
about itself becomes untrustworthy.  These are mechanical doc/count/hygiene
fixes, but they matter to anyone evaluating the project.

## Scope

- In scope: reconcile prose with source (admit claim, counts, combinator list,
  test/line numbers), delete dead types, de-duplicate fsdoc, reconcile rlimit
  drift, clean up session detritus, verify fork-tag/`.NET 10` reachability.
- Out of scope: new combinators/backends/, behavioral changes, F\* formatter
  work (broken upstream — see codec-cleanup-formatting T4.3).

## Definition of done

- Every C/M/W finding resolved or explicitly deferred with a written reason;
  all S findings tracked.
- Source still 0-admit; `nix flake check` + `nix build .#native .#ocaml .#fsharp`
  GREEN.
- No prose (README/AGENTS/headers/CHANGELOG/openspec) asserts a number the
  source contradicts.
