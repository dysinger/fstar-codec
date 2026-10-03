# Change Proposal: codec-layer-sort

## Summary

Reorganize `Data.Codec.Types.fst` out of its current "functional interleaving"
(the file mixes lemmas and non-lemma helpers throughout, in proof-dependency
order) into an explicit **layered** structure:

```
Layer 1 — Core types + primitive helpers   (alphabetical)
Layer 2 — Decode/scan/encode helpers        (alphabetical)
Layer 3 — Proof lemmas                      (topological + alphabetical)
Layer 4 — Combinators + composite helpers   (alphabetical)
Layer 5 — Expansion lemmas                  (alphabetical)
```

Every layer defines what the next layer needs; each layer is sorted, with F*'s
definition-before-use constraint satisfied within and across layers.

## Motivation

The current 2820-line module interleaves 80 lemmas with 83 non-lemma
definitions.  Lemmas are grouped by *subsystem* (Bytes/Varint/Digit/Infra) but
the grouping is not declared as layers, stray non-lemma helpers
(`u32_of_small_nat`, `shift_result`, `nat_add`, `nat_incr`) sit *inside* lemma
clusters, and lemmas are not alphabetically sorted.  A reader cannot tell at a
glance which definitions are foundational and which are leaves.

## What we know (verified this session)

- **No forward references exist** in the module (comment-stripped analysis of
  all 163 top-level defs).  The current order is a valid topological order.
- **80 lemmas form a 23-edge DAG** (lemma→lemma), plus edges from lemmas to
  non-lemma helpers (`bytes_decode`, `varint_decode_go`, `acc_digits`,
  `all_digits`, `is_digit`, `dec_nat`, `pow2`, `nbytes_of_varint`,
  `satisfy_run_scan`, …).  A *single alphabetical lemma block* is therefore
  **not** feasible — dependency order must be honored.
- **Two lemma kinds:**
  - **Proof lemmas** (65) — used *by* combinators (`lemma_bytes_decode_*`,
    `lemma_varint_*`, `lemma_digits_*`, `lemma_seq_*`, `lemma_slice_*`,
    `lemma_satisfy_*`, `lemma_word32_enc_bytes`, …).
  - **Expansion lemmas** (15) — document a combinator's fields and must come
    *after* it: `lemma_byte_val_{wfcv,wfcv_prop,rest_cond}_eq`,
    `lemma_digits_to_int_{wfcv,rest_cond}_eq`,
    `lemma_map_{wfcv,wfcv_prop,rest_cond,enc,dec}_eq`,
    `lemma_product_{wfcv,wfcv_prop,rest_cond,enc,dec}_eq`.

## Non-goals

- No change to the proof content (bodies, rlimits, SMTPat, admits).
- No change to the `codec a` record, combinator signatures, or public API.
- No change to `Data.Codec.Pulse` / `Data.Codec` / test modules (this is
  `Data.Codec.Types` only).

## Approach — the correct method (not one big script)

Do the reorg **incrementally and mechanically-verifiably**, layer by layer,
re-verifying `nix develop -c make check` (0-admit gate) after every move.  F*
is the oracle: any out-of-order reference surfaces as Error 72/241/… ("name not
found in scope") and is fixed by moving that one def earlier.

The prior session's attempt to automate the whole reorg with a single
line-based splitter failed because the module has *inconsistent doc-comment
placement* in a handful of places (e.g. `pow2` carries both a `(** pow2 *)`
section header and a `(** pow2. *)` def doc with a `(* *)` block and
`#push-options` sandwiched between; `codec` is a `type` wrapped in its own
`#push`/`#pop`).  A mechanical "walk back over comments to find each def's
verbatim block" is not robust there.

The correct method (see tasks.md) reconstructs each def's block from its
**`#push-options` … `#pop-options` pairing** — which *is* reliable (66 balanced
pairs) — and treats the `#pop-options` line as the hard end-boundary of a
block.  Section banners and def docs travel with the def they precede.

## Definition of done

- `Data.Codec.Types.fst` is 5 explicit layers, each sorted (proof lemmas in
  topo+alphabetical order), separated by a `(** Layer N — <name>. *)` banner.
- `make check` verifies all 6 modules 0-admit GREEN.
- `nix build .#checked .#native .#ocaml .#fsharp` + `nix flake check` GREEN.
- No `admit`/`assume`/`magic`; 100% lemma coverage unchanged.
- The module `@section` header and README/API combinator list still accurate.
