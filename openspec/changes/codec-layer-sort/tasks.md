# Implementation Tasks: codec-layer-sort

**Change**: reorganize `Data.Codec.Types.fst` into 5 explicit layers, each
sorted (proof lemmas in topo+alphabetical order), satisfying F*'s
definition-before-use across and within layers.

> ⚠️ **MANDATE:** every `make check` / `nix build` is wrapped in a hard timeout.  A
> `make check` that should take ~2 min but runs 10+ min is a non-terminating SMT
> query (the Pulse varint hang symptom), not patience — kill it and bisect.

> **Why not one big script.**  A single line-based reorder was attempted and
> abandoned this session: the module has inconsistent doc-comment placement in
> a few spots (duplicate `(** pow2 *)`/`(** pow2. *)`, a `(* *)` block and
> `#push-options` between a section header and its def, `codec` as a `type`
> wrapped in `#push`/`#pop`).  The robust unit boundary is the **balanced
> `#push-options`/`#pop-options` pairing** (66 pairs, all matched) — a block
> ends at its `#pop-options`, full stop.

## Phase 0 — Tooling: a correct unit-extractor (the "experiment")

- [ ] **T0.1 — Write `reorg_extract.py` that splits into units by `#pop-options`.**  A
      unit = everything from the line after the previous unit's `#pop-options`
      (or the preamble's last line) through *this* unit's `#pop-options`,
      inclusive.  Defs with **no** `#push`/`#pop` wrapper form "bare" units that
      this splitter must still assign correctly by tracking the nearest
      subsequent `#pop-options` as the boundary.  **Verify: 163 units, 0
      `#push`/`#pop` imbalance per unit, 0 overlap, 0 gap** (the exact three
      invariants the prior splitter violated).
- [ ] **T0.2 — Unit = def name + verbatim text + (push?/pop?) flags.**  Confirm
      each unit's def name by matching its `let`/`let rec`/`type` line; assert
      that concatenating all units == the original stripping only *trailing*
      blank lines.
- [ ] **T0.3 — Dry-run reorder without writing.**  Print the target layer
      assignment for all 163 defs; eyeball that section banners (`(** Core Types *)`,
      `(** Digit helpers *)`, …) travel with the correct def and that
      `pow2`/`codec`/`varint` (the known-tricky ones) land where expected.

## Phase 1 — Layer 1 (core types + primitives), alphabetical

- [ ] **T1.1 — Classification.**  `byte, byte_seq, error_code, decode_error,
      decode_result, codec, mk_decode_error, nat_of_int, u32_of_nat,
      u32_of_small_nat, pow2, nat_add, nat_incr, dec_nat, len_of_enc` (15 defs).
- [ ] **T1.2 — Order within the layer is dependency-constrained, not purely
      alphabetical.**  `codec` must follow `byte_seq`+`decode_result`+
      `decode_error`; `len_of_enc` must follow `codec`.  Emit the 15 in
      topo+alphabetical order (compute the layer-restricted DAG first).
- [ ] **T1.3 — `make check` GREEN before proceeding.**

## Phase 2 — Layer 2 (decode/scan/encode helpers), alphabetical

- [ ] **T2.1 — The 44 non-lemma, non-combinator helpers.**  Includes
      `string_to_bytes`, `bytes_decode`, `varint_decode_go`, `varint_encode_go`,
      `digits_encode`, `is_digit`, `acc_digits`, `all_digits`,
      `digits_to_int_decode_go`, `digits_to_int_decode`, `shift_result`,
      `nbytes_of_varint`, `satisfy_run_scan`, `satisfy_run_dec`,
      `scan_until_split/content/rest`, `take_until_dec/enc/wfcv/wfcv_prop/rest_cond`,
      `one_of_mismatch_evident/enc/dec/mem`, `count_enc_list/dec_list/wfcv_prop_list/rest_cond_list/roundtrip_list`,
      `alt_enc/dec/wfcv/wfcv_prop/rest_cond/roundtrip/dec_err_bound/dec_consumed_bound`,
      `is_prefix_of`.
- [ ] **T2.2 — Topo+alphabetical within the layer.**  Several helpers *are*
      the `.dec`/`.enc`/`.wfcv`/`.roundtrip` of a later combinator and
      reference `codec`/`decode_result`/`mk_decode_error` — keep them
      dependency-ordered.
- [ ] **T2.3 — `make check` GREEN.**

## Phase 3 — Layer 3 (65 proof lemmas), topo+alphabetical

- [ ] **T3.1 — The precomputed order already exists** (saved in `/tmp` this
      session: a topological sort of the 65 proof lemmas breaking ties
      alphabetically, respecting all 23 lemma→lemma edges).  Re-derive it from
      the exact 20-edge list in `proposal.md`-adjacent notes, or re-run the
      topo+alpha queue on the 65 names.
- [ ] **T3.2 — Proof lemmas only in this layer.**  Exclude the 15 expansion
      lemmas (they stay in Layer 5).
- [ ] **T3.3 — Sort + emit; `make check` GREEN.**  This is the big one — 65
      defs move.  If F* reports a "not in scope" error, the *target* lemma
      references a lemma that must appear earlier: move just that dependency
      earlier and re-check (do not re-sort the whole layer).

## Phase 4 — Layer 4 (24 combinators + composite helpers), alphabetical

- [ ] **T4.1 — The 22 combinators + `one_of`/`take_until`.**  `token`,
      `byte_val`, `satisfy`, `pure`, `text`, `bytes`, `uint8`, `word16be/le`,
      `word32be/le`, `varint`, `digits_to_int`, `custom`, `product`, `sum`,
      `map_`, `count`, `label`, `alt`, `satisfy_many0/1`, `one_of`, `take_until`.
- [ ] **T4.2 — Dependency-ordered within.**  `varint` needs `nbytes_of_varint`
      (Layer 2) + `lemma_varint_encode_decode_roundtrip` (Layer 3); `alt` needs
      its `alt_enc/dec/wfcv/…` helpers (Layer 2) + `alt_roundtrip` (Layer 2);
      `take_until`/`one_of` need their helper tuples (Layer 2).
- [ ] **T4.3 — `make check` GREEN.**

## Phase 5 — Layer 5 (15 expansion lemmas), alphabetical

- [ ] **T5.1 — The `*_eq` lemmas that document combinator fields** (see
      proposal.md).  Sorted alphabetically.
- [ ] **T5.2 — `make check` GREEN.**

## Phase 6 — Final gate + docs

- [ ] **T6.1 — `nix build .#checked .#native .#ocaml .#fsharp` + `nix flake check` GREEN.**
- [ ] **T6.2 — No admits/assume/magic; 100% lemma coverage unchanged** (the
      anchors reference names, not positions, so they survive the reorder).
- [ ] **T6.3 — Update the module `@section` header** to describe the 5 layers.
- [ ] **T6.4 — Record the lesson in the fstar skill** (§ — "reordering a
      proof-heavy module: extract units by balanced `#push`/`#pop`, topo+alpha
      per layer, F* as the ordering oracle").

## Definition of done

Five explicit layers, each sorted, `make check` + 4 nix targets + flake check
GREEN at 0-admit, lemma coverage 100%, docs refreshed.
