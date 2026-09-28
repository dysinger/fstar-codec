# Implementation Tasks: pulse-fsdoc-finalize

**Change**: finish the `codec-cleanup-formatting` leftovers — regroup/fsdoc
`Data.Codec.Pulse`, fsdoc-audit the pure spec, and run the real nix build gate.

> ⚠️ **MANDATE (unchanged from AGENTS.md):** every `fstar.exe` / `nix build` /
> `make` is wrapped in a hard timeout (`(sleep N && kill -9 $pid) & guard`).
> Re-verify (0-admit) after *every* reorder — a moved `fn`/`let` must not break
> its proofs.  Budget: fstar verify ≤ 10 min, `nix build` ≤ 15 min.

## Phase 1 — Regroup + fsdoc `Data.Codec.Pulse` (T1 from codec-cleanup-formatting)

The current order in `src/Data.Codec.Pulse.fst` (1107 lines) is:
types → `encode_token` / `encode_byteval` / `encode_uint8` / `encode_word16be` /
`encode_word32be` / `encode_word16le` / `encode_word32le` / `varint_encode_pred`
+ `encode_varint` → decoders (same ad-hoc order) → dispatchers → lemmas
(ad-hoc order).

Target order (alphabetical within each group):

- [ ] **T1.1 — Types block.**  Keep `codec_t`, `error_code_c`, `decode_error_c`,
      `decode_result_ok`, `decode_result_c` contiguous, each with fsdoc (already
      mostly present — verify).
- [x] **T1.2 — Encoders, alphabetical (non-varint) + varint last.**
      `encode_byteval`, `encode_token`, `encode_uint8`, `encode_word16be`,
      `encode_word16le`, `encode_word32be`, `encode_word32le`, then
      `varint_encode_pred` (immediately above) `encode_varint`.
      **CRITICAL FINDING (landed):** `encode_varint`/`varint_encode_pred` MUST
      stay **after** the word encoders.  Moving them earlier (alphabetical
      middle) puts the 5-way varint case-split in scope *before*
      `lemma_pulse_roundtrip_word32be`, tipping that already-fragile word32 SMT
      query from "slow (~90s)" into a **non-terminating z3 spin (100% CPU)**.
      Varint stays last: it is the odd-one-out (deferred-length 5-byte) and its
      placement is the proven-green SMT order.
- [x] **T1.3 — Decoders, alphabetical (non-varint) + varint last.**
      `decode_byteval`, `decode_token`, `decode_uint8`, `decode_word16be`,
      `decode_word16le`, `decode_word32be`, `decode_word32le`, then
      `varint_decode_expected` (immediately above) `decode_varint`.  Same
      SMT-scope constraint as encoders.
- [ ] **T1.4 — Dispatchers.**  `encode_bytes` then `decode_bytes`, fsdoc'd.
- [x] **T1.5 — Lemmas.**  `lemma_pulse_roundtrip_{byteval,token,uint8,word16be,
      word16le,word32be,word32le}` then `lemma_varint_roundtrip_smtpat` (must sit
      **after** word32le — its SMTPat trigger otherwise pollutes the word-lemma
      SMT queries) + `lemma_pulse_roundtrip_varint` (must sit **after** smtpat,
      which it depends on) + `lemma_pulse_encode_decode_match`.
- [x] **T1.6 — Re-verify `Data.Codec.Pulse`** after the reorder — GREEN, 0-admit
      (`All verification conditions discharged successfully`, < 5 min @ rlimit 120).

> Note: `varint_encode_pred` / `varint_decode_expected` / `lemma_varint_roundtrip_
> smtpat` must stay `noextract` (they use `Seq`/`Prims.int`).  Do **not** reorder
> such that a `fn`/`let` moves before the type/helper it depends on.

## Phase 2 — fsdoc audit on the pure spec (T1.6 from codec-cleanup-formatting)

- [ ] **T2.1 — `Data.Codec.Types` (2644 lines).**  Every public `type`, `let`
      codec/combinator, and `Lemma` carries `(** … *)` fsdoc.  Fill gaps (the
      tail combinators `alt`, `one_of`, `take_until`, and the `lemma_*_eq`
      refinement lemmas are the likely gaps).
- [ ] **T2.2 — `Data.Codec` (127 lines).**  Same audit (derived combinators +
      char predicates).
- [ ] **T2.3 — Re-verify both** after any doc-only edits (should be a no-op
      re-verify, but confirm).

## Phase 3 — Real nix build gate (T5.2 from codec-cleanup-formatting)

The previous session only verified via a hand-rolled `fstar.exe` driver and
`nix eval .#X.name` (cheap name-string eval).  The actual builds/checks were
**never run**.  Do them now (guarded):

- [ ] **T3.1 — `nix build .#native`** (C11 shared/static lib).  Confirm
      `libcodec.{dylib,so,a}` + `codec.h` are produced (note: names changed from
      `libfstar-codec.*`/`fstar_codec.h` — see the `pname = "codec"` change).
- [ ] **T3.2 — `nix build .#ocaml`** (OCaml findlib package).
- [ ] **T3.3 — `nix build .#fsharp`** (.NET library via `.NET 10`).
- [ ] **T3.4 — `nix flake check`**, including the new `.#formatting` target
      (`treefmt-nix` wired in the previous session).
- [ ] **T3.5 — `nix develop && make check`** as an end-to-end dev-loop smoke
      test (the previous session used a direct driver, not this path).

## Phase 4 — Land the record

- [ ] **T4.1 — Update `AGENTS.md`** handoff state: mark
      `codec-cleanup-formatting` T1/T5 done, point at this change as the new
      "next steps", and record any new findings (artifact-name change, backend
      build results, `.NET 10` status).
- [ ] **T4.2 — Update the backend matrix** in `AGENTS.md` § "Backend matrix" if
      `#fsharp`/`#ocaml` build results differ from the current `🟡`/`✅` marks.

## Definition of done

- `Data.Codec.Pulse` grouped + sorted, fully fsdoc'd, 0-admit.
- `Data.Codec.Types` + `Data.Codec` fsdoc-audited, 0-admit.
- `nix build .#native .#ocaml .#fsharp` + `nix flake check` all GREEN.
