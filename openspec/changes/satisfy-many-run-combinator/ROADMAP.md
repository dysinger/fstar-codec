# ROADMAP — variable-width codec primitives (multi-session)

This is the master plan for the missing **variable-width** building blocks in the
record-`codec` library, and the downstream packages that consume them.  It spans
`fstar-codec` (the primitive), the Round-2 extractions (`fstar-mime` first), and
the eventual protobuf package.  Treat it as the canonical source of truth for all
sessions until every session is done.

> **Why this is one plan, not three.**  The same missing primitive — "consume a
> run of bytes matching a predicate" — is required for **text** formats (MIME
> token runs, HTTP header values, unpadded base encodings), **binary** formats
> (null/line-terminated runs, length-delimited chunks), and **protocol buffers**
> (base-128 varint already exists; `length-delimited` and `sint` zigzag do not).
> Adding it once, generically and verified, unblocks all three.

---

## The primitives we need (in dependency order)

| # | Primitive | Type | Status | Consumers |
|---|-----------|------|--------|-----------|
| 1 | `satisfy_many0` | `(byte -> bool) -> codec (list byte)` | **missing** | mime tokens, header values, text runs |
| 2 | `satisfy_many1` | `(byte -> bool) -> codec (list byte)` | **missing** | `type`/`subtype`, non-empty runs |
| 3 | `varint` (base-128) | `codec int` | **exists** | protobuf wire-type 0 |
| 4 | `zigzag` (sint) | `int -> int` (wired pair) | **missing** | protobuf `sint32`/`sint64` |
| 5 | `length_delimited` | `codec a -> codec a` (len-prefixed) | **missing** | protobuf wire-type 2, binary chunks |
| 6 | `fixed32`/`fixed64` | `codec int32/int64` | **partial** (`word32le/be` exist) | protobuf wire-type 1/5 (LE) |

The immediate scope is **#1 and #2** (`satisfy_many0/1`).  #3 exists.  #4–#6 are
protobuf-specific and are a **later session** (see Session C), gated on #1/#2
landing and the Round-2 consumers below.

---

## Session A — `satisfy_many0/1` in `fstar-codec`

**Change**: `openspec/changes/satisfy-many-run-combinator/` (already written:
`proposal.md`, `specs/codec/spec.md`, `tasks.md`).

**Goal**: ship `satisfy_many0` / `satisfy_many1` as generic (symbolic-`f`)
`codec` records with a generic roundtrip, in `Data.Codec.Types`, at 0-admit,
`--z3rlimit ≤ 120`, 4/4 targets green.

**Key facts to carry forward** (from the proposal + §60b):
- The run scan is a **top-level `let rec` over the byte list** (NOT nested —
  Warning 242).
- Framing = `rest_cond xs r = (Seq.length r = 0 ∨ not (f (Seq.index r 0)))`.
- The roundtrip is proven **inside** `Data.Codec.Types` (where
  `lemma_seq_to_list_of_list_append` is transparent) — the §11-correction.
- Reference proof already exists in-tree: `lemma_digits_process_list` (the
  `is_digit` run roundtrip); generalize `is_digit → f`.

**Sub-tasks**: follow `tasks.md` Phase 1→5.  Do NOT begin Phase 2 until the
Phase-1 spike (symbolic-`f` roundtrip) verifies under the full nix build — LSP
is looser than `fstar.exe --z3rlimit` (§3/§5 of the skill).

**Exit criteria**: 4/4 nix targets + `flake check` GREEN; `grep` admits/assume
empty in `src/`; coverage anchors in `test/Data.Codec.Test.Integration.fst`;
`CHANGELOG.md` + `API.md` updated.

---

## Session B — rewire `fstar-mime` onto `satisfy_many1` (Mandate-22 fix)

**Change**: new `fstar-mime` change (write it next session, or now): delete the
bespoke `token_run_scan`/`mime_bytes_enc`/`mime_bytes_dec` and rebuild:

```fstar
let mime_codec : codec mime =
  equiv_map
    (fun ((t, _), sub) -> Some (mime_of_bytes { type_bytes = t; subtype_bytes = sub }))
    (fun m -> Some ((string_to_ascii_bytes m.type_, ()), string_to_ascii_bytes m.subtype))
    (product (satisfy_many1 is_token_char)
             (drop_then (byte_val 0x2Fuy) (satisfy_many1 is_token_char)))
```

`encode_mime` / `decode_mime` become thin `mime_codec.enc` / `.dec` wrappers.
The `string` view (`mime_of_string`/`string_of_mime`) stays a pure function;
the roundtrip is the codec's (byte-list) `.roundtrip` + concrete vectors, NOT a
general symbolic `string` roundtrip (§45).

**Steps**:
1. Pin `fstar-mime`'s `fstar-codec` flake input to the new commit (local
   `git+file:` first, then published `github:dysinger/fstar-codec`).
2. Delete bespoke codec; rewire; re-verify 0-admit (`#checked`).
3. Re-run 4/4 targets + `flake check`.
4. Publish `github:dysinger/fstar-mime`; clean-clone verify (x86 via Lima +
   aarch64-darwin).
5. Delete the monorepo `mime/` dir (backed up), unwire from `flake.nix`.

**Exit criteria**: `fstar-mime` has **zero** bespoke encode/decode (Mandate 22);
4/4 targets + flake check GREEN; published.

---

## Session C — protobuf package (`fstar-protobuf`) — later, gated on A/B

**Precondition**: Session A landed, and the Round-2 text/binary deps (`mime`,
`text`, `dns`, `http`) progressed far enough that the protobuf wire format's
consumers are coherent.

**Goal**: a `fstar-protobuf` repo exposing the proto3 wire format (RFC: protobuf
wire types) as verified codecs:

- **wire-type 0 (Varint)**: reuse `varint` (base-128 exists).
- **wire-type 1 (64-bit) / 5 (32-bit)**: `fixed64le`/`fixed32le` (`word64le`
  is missing — add `word64le` to `fstar-codec` alongside `word16le/32le`).
- **wire-type 2 (Length-delimited)**: `length_delimited : codec a -> codec a`
  (a `varint` length prefix + `count`-bounded payload) — a **new codec
  combinator** in `fstar-codec`, proven like `product`/`count`.
- **wire-type 5 vs signed**: `zigzag` encode/decode for `sint32`/`sint64`
  (the protobuf non-two's-complement sign encoding) — a small pure pair proved
  by `FStar.Int` bit-vector lemmas.
- **field framing**: `tag = (field_number << 3) | wire_type` (a `varint`), then
  `map_`/`product`/`alt`/`one_of` over the field set.

This is a **new** package (no existing `proto/` dir or `openspec/specs/protobuf`).
Write a new OpenSpec change (proposal + specs + tasks) when Session C starts.

**Dependencies**: `satisfy_many1` (A), and `word64le` + `length_delimited` +
`zigzag` additions to `fstar-codec` (these are a small **same-repo** follow-up to
A — they do not block B).

---

## Cross-session invariants (do not regress)

1. **Mandate 22 is absolute.**  A new package needing "run of bytes" must use
   `satisfy_many1` — never write a per-package scanner.  If a *new* primitive is
   needed (e.g. `length_delimited`, `word64le`), add it to `fstar-codec`, prove
   it generically, and consume it via the flake dep.
2. **Roundtrips live in `Data.Codec.Types`.**  Any generic roundtrip that needs
   the §11 `seq_to_list` bridge must be placed there (transparent), not at a
   consumer.
3. **LSP is not the gate.**  Every session ends with `nix build .#checked` +
   `.#native .#ocaml .#fsharp` + `nix flake check` GREEN; `grep` admits/assume
   empty in `src/`.
4. **Skill is the memory.**  After each session, record any newly-verified
   lesson in `~/.pi/agent/skills/fstar` and commit it.  §60b (Session A's
   lesson) is already committed (`a041e66`).

## Status ledger

| Session | Work | Status |
|---------|------|--------|
| A | `satisfy_many0/1` in fstar-codec | ✅ done (0-admit, 4/4 targets + flake GREEN) |
| B | fstar-mime rewire (Mandate-22 fix) | 🟡 planned (blocked on A) |
| C | fstar-protobuf (wire format) | ⚪ future (blocked on A + Round-2 deps) |
