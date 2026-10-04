# Data.Codec.Types

Data.Codec.Types — Core types, record codec, helpers, lemmas, and combinators.
This module defines the bidirectional codec framework: a [codec a] is a
verified serializer/deserializer pair with roundtrip, error-bounds, and
n-bounds proofs.  All 22 combinators are standalone functions
returning codec records — no GADT, no n, no mutual recursion.
- [codec a] — 8-field record: enc, dec, wfcv, wfcv_prop, rest_cond,
roundtrip, dec_err_bound, dec_consumed_bound
- [error_code] — sum type of parse errors
- [decode_error] — error record with position and optional label
- [decode_result a] — either an error or a value + bytes consumed
Leaf: token, byte_val, satisfy, pure, text, bytes, uint8,
word16be, word16le, word32be, word32le, varint, digits_to_int
Combinator: custom, product, sum, map_, count, label, alt,
satisfy_many0, satisfy_many1
All lemmas are called explicitly in roundtrip proofs.  SMTPat is used
sparingly and only on pattern-matching decoders (bytes_decode,
lemma_seq_cons_append).
Every combinator carries its own roundtrip, dec_err_bound, and
dec_consumed_bound proof.  Z3 rlimits are kept ≤ 120 via structural
decomposition, with three documented exceptions: the
[lemma_seq_to_list_of_list_append] bridge and the two
[take_until] error/consumed-bound lemmas ([lemma_take_until_dec_err_bound],
[lemma_take_until_dec_consumed_bound]) each need a higher scoped rlimit
(2000 / 400) — see the inline comments at [Data.Codec.Types].  Zero admits
across all 22 combinators.

---

Expected exactly N bytes, got fewer.
Used by [text] combinator for fixed-string matching.
Distinct from [UnexpectedEndOfInput] which is general.

---

Text literal mismatch in [text] combinator.

---

Construct a [decode_error] with no label.
Use this instead of record literal to ensure [label = None] by default.

---

Result of decoding: either an error or a value plus bytes consumed.

---

Clamp negative integers to 0.
Negative inputs are silently clamped to 0.  All codec wfcv guards
reject negative values before reaching encoders, so this clamping
is only a safety net for unguarded calls.  If [nat_of_int] receives
a negative argument, the wfcv precondition failed first.

---

Convert [nat] to [U32.t], clamping values ≥ 2^32 to 2^32−1.
Prefer [u32_of_small_nat] when you have a proof that [n < 4294967296].
Only use this when clamping is acceptable (e.g., error positions that
are already bounded by buffer length).

---

A verified bidirectional codec for values of type ['a].
Eight fields:
- [enc]: serializer from ['a] to [byte_seq]
- [dec]: deserializer from [byte_seq] to [decode_result a]
- [wfcv]: well-formed-value guard (runtime-checkable)
- [wfcv_prop]: well-formed-value property (proof-only, e.g., [v == x] for pure)
- [rest_cond]: suffix condition — what must hold of bytes after the encoded value
- [roundtrip]: lemma proving [dec (enc v ++ r) == Inr (v, |enc v|)]
when [wfcv], [wfcv_prop], and [rest_cond] hold
- [dec_err_bound]: lemma proving error position ≤ input length
- [dec_consumed_bound]: lemma proving consumed bytes ≤ input length

---

string_is_ascii: true iff every character in s has code point < 128.
Use as wfcv guard for text combinators to prevent silent truncation.

---

Decode a digit string to integer, bounded by max digits and predicate.

---

Lemma: [10 < 2^32], proved by normalization.

---

Convert a nat known to be [< 2^32] into a [U32.t] without clamping.
Requires proof that [x < 4294967296].

---

Lemma: U32.v (u32_of_small_nat x) == x for bounded x.

---

lemma_u32_bound and lemma_bound_10 are convenience wrappers.

---

Lemma: n ≤ U32.v len implies n < 2^32.

---

Lemma: x ≤ 10 implies x < 2^32.

---

Lemma: error position shifted by buffer offset stays within U32 range.

---

Lemma: seq_of_list (seq_to_list s) == s (roundtrip identity).

---

Lemma: seq_to_list (seq_of_list l) == l (roundtrip identity).

---

Lemma: Seq.length (seq_of_list l) == List.Tot.length l.

---

Lemma: SMTPat unfold for bytes_decode on a cons list.

---

Lemma: successful bytes_decode consumes exactly |bs| bytes.

---

Lemma: bytes_decode error position is bounded by the byte list length.

---

Proves that bytes_decode error positions are bounded by the input length.

---

Stronger than lemma_bytes_decode_inl_bound (which bounds by |bs|).

---

Lemma: successful varint decode consumed is in (pos, pos+fuel].

---

Lemma: varint decode with fuel=10 consumes at most 10 bytes.

---

Proves that a successful varint decode never consumes more bytes

---

Lemma: varint decode error position ≤ input length.

---

Lemma: digits decode go bounds both Inr consumed and Inl err_pos.

---

Digit lemma infrastructure

---

lemma_word32_enc_bytes: given 4 bytes and a nested-append sequence,

---

proves the bytes are at the expected indices. Parametric over byte values

---

so it can be called from roundtrip proofs without self-reference.

---

Combinator 2: byte_val — a specific expected byte.
Encodes [b] (1 byte).  Decodes one byte; succeeds if it equals [b],
fails with [ExpectedByte b] otherwise.

| Parameter | Description |
|-----------|-------------|
| `b` | The exact byte to match. |

---

Combinator 3: satisfy — a byte matching a predicate.
Encodes as [Seq.create 1 v].  Decoder rejects bytes failing [f]
with [ExpectedPredicate].  The wfcv guard is [f v].

| Parameter | Description |
|-----------|-------------|
| `f` | Predicate the byte must satisfy. |

---

Combinator 4: pure — a constant value (zero bytes on the wire).
Encodes as empty sequence.  Decoder always returns [x] with 0 bytes
n.  wfcv_prop requires [v == x].

| Parameter | Description |
|-----------|-------------|
| `x` | The constant value. |

---

Combinator 5: text — a fixed ASCII string.
Encodes as [string_to_bytes s].  Decodes exactly [n] bytes and
compares with [string_to_bytes s].  Fails with [ExpectedEndOfInput]
if input is too short, [ExpectedText] on mismatch.
wfcv requires [string_is_ascii s].

| Parameter | Description |
|-----------|-------------|
| `s` | The expected string (ASCII only). |

---

Combinator 6: bytes — a fixed byte sequence.
Encodes as [seq_of_list bs].  Decoder uses [bytes_decode] for
exact byte-by-byte matching.  Fails with [ExpectedByte b] on
mismatch at the first differing position.

| Parameter | Description |
|-----------|-------------|
| `bs` | The expected byte list. |

---

Combinator 7: uint8 — unsigned 8-bit integer.
Encodes as a single byte.  wfcv: [0 <= v < 256].
Decoder returns [U8.v] of the byte.

---

Combinator 8: word16be — big-endian 16-bit integer.
Encodes as 2 bytes (hi, lo).  wfcv: [0 <= v < 65536].
Decoder: [hi*256 + lo].

---

nbytes_of_varint: single source of truth for varint encoding length.

---

Used by varint.enc, lemma_varint_encode_decode_roundtrip, and encode_varint.

---

For values n >= 2^35, returns 6. The varint combinator's wfcv restricts

---

to v < 2^35, so the 6-byte case is unreachable for valid codec values.

---

lemma_nbytes_of_varint_bound: for values in varint range, nbytes <= 5.

---

Explicit 5-range case split — no SMT-only quantifier reasoning.

---

lemma_nbytes_of_varint_correct: encoded length matches nbytes_of_varint.

---

Combinator 12: varint — variable-length integer, unsigned LEB128 encoding.
Encodes values in [0, 2^35) as 1-5 bytes.  wfcv: [0 <= v < 34359738368].
Decoder uses 10-byte fuel limit (well beyond the 5-byte maximum).
Encoding length is determined by [nbytes_of_varint] — the single source
of truth.  Per-nbytes roundtrip lemmas ([lemma_varint_enc_dec_{1..5}byte])
prove each length case.  Five arithmetic lemmas ([lemma_varint_{2..5}byte_arithmetic])
provide the integer decomposition identities.
C extraction: Pulse layer provides a U32.t-bounded encoder with
[varint_encode_pred] byte-level specification.

---

NOTE: digits_to_int accumulator and varint_decode_go value parameter

---

use unbounded F* `int`. C extraction will need bounds checks

---

Per-nbytes encode→decode lemmas. Each characterizes the roundtrip for

---

a fixed encoding length. The arithmetic identities are extracted into

---

standalone lemmas (lemma_varint_*byte_arithmetic) so the roundtrip lemmas

---

only need to connect encode/decode byte values, not re-prove the

---

Uses direct-n ensures (no intermediate bindings) for caller compatibility.

---

Arithmetic identity: n = 128^2*(n/16384) + 128*((n/128)%128) + n%128.

---

Uses direct-n ensures (no intermediate bindings) for caller compatibility.

---

Arithmetic identity: n = 128^3*(n/2097152) + 128^2*((n/16384)%128) + 128*((n/128)%128) + n%128.

---

Uses direct-n ensures (no intermediate bindings) for caller compatibility.

---

Arithmetic identity: n = 128^4*(n/268435456) + 128^3*((n/2097152)%128) + 128^2*((n/16384)%128) + 128*((n/128)%128) + n%128.

---

Expressed directly in terms of n (no intermediate bindings) so callers

---

Structural lemma: varint encode → decode roundtrip on [0, 2^35).

---

Proved by explicit 5-range case analysis, each calling a per-nbytes lemma

---

Combinator 13: digits_to_int — parse a digit string to integer.
Encodes as [seq_of_list (digits_encode (nat_of_int v))].
wfcv: [pred v] and encoding length ≤ [n].
rest_cond: suffix does not start with a digit.
Fails with [ExpectedPredicate] if input doesn't start with a digit.

| Parameter | Description |
|-----------|-------------|
| `n` | Maximum number of digits to read. |
| `f` | Validation predicate on the parsed integer. |

---

Combinator 14: custom — user-supplied codec with caller-provided proofs.
Zero admits.  The caller must supply all 6 proof functions.
This is the verified extension point — no escape hatch.
The decoder takes [byte_seq] (not [list byte]) to avoid
[seq_to_list] overhead.

| Parameter | Description |
|-----------|-------------|
| `d` | Decoder function. |
| `e` | Encoder function. |
| `wfcv_custom` | Well-formed-value guard. |
| `wfcv_prop_custom` | Well-formed-value proposition. |
| `rest_cond_custom` | Suffix condition. |
| `roundtrip_custom` | Roundtrip lemma. |
| `dec_err_bound_custom` | Error position bound lemma. |
| `dec_consumed_bound_custom` | Consumed bytes bound lemma. |

---

Bridges c1.dec_err_bound and c2.dec_err_bound across the slice offset.

---

c1.dec_consumed_bound proves that n1 <= Seq.length input when c1.dec

---

Bridges c1.dec_consumed_bound and c2.dec_consumed_bound across the slice.

---

c1.dec_consumed_bound proves that n1 <= Seq.length input when c1.dec

---

Combinator 15: product — sequential pair.
Encodes [(v1, v2)] as [c1.enc v1 ++ c2.enc v2].
Decodes c1 then c2 on the suffix; errors from c2 have positions
shifted by the bytes c1 n.
wfcv: [c1.wfcv v1 && c2.wfcv v2].
rest_cond: chains both sub-conditions inductively.
Called [product] because it forms a monoidal product (not a tuple
constructor — the F* tuple type is written [a & b]).

| Parameter | Description |
|-----------|-------------|
| `c1` | First codec, decoding ['a] from the prefix. |
| `c2` | Second codec, decoding ['b] from the remaining suffix. |

---

Bridges c1.dec_err_bound and c2.dec_err_bound across the +1 tag offset.

---

Written against the inline decoder logic (not (sum c1 c2).dec)

---

When s is empty: proves 0 <= Seq.length input (trivially true from nat).

---

Bridges c1.dec_consumed_bound and c2.dec_consumed_bound across the +1 tag offset.

---

Combinator 16: sum — tagged union.
Encodes [Inl v1] as tag byte [0x00] followed by [c1.enc v1].
Encodes [Inr v2] as tag byte [0x01] followed by [c2.enc v2].
Decoder reads the first byte as a discriminator:
[0x00] → delegate to c1, [0x01] → delegate to c2,
anything else → [ExpectedSumTag].
Error positions from sub-decoders are shifted by +1 (the tag byte).

| Parameter | Description |
|-----------|-------------|
| `c1` | Codec for the [Inl] (left) branch. |
| `c2` | Codec for the [Inr] (right) branch. |

---

Combinator 17: map_ — value transformation.
Encoder applies [g]; if [None], produces [Seq.empty].
Decoder uses [c.dec], then applies [f] to the result.
wfcv: [g v == Some a_val] and [f a_val == Some v] and [c.wfcv a_val].
Used to build [choice], [then_drop], [drop_then], [between], [optional].

| Parameter | Description |
|-----------|-------------|
| `f` | Maps decoded ['a] to optional ['b].  [None] → [ExpectedPredicate]. |
| `g` | Maps ['b] to optional ['a] for encoding. |
| `c` | The underlying codec. |

---

Lemma: count encode then decode roundtrip.

---

count_dec_list error position bound: when it returns Inl, err_pos <= |s|

---

Combinator 18: count — fixed-count repetition.
Encodes [n] elements sequentially.  Decoder reads exactly [n]
elements; fails if any sub-decoder fails.  wfcv: list length = [n]
and all elements satisfy [c.wfcv].

| Parameter | Description |
|-----------|-------------|
| `n` | Exact number of elements to encode/decode. |
| `c` | Element codec. |

---

Combinator 19: label — attach a descriptive name to a codec.
Successful decodes pass through unchanged.  On error, the label
is set to [Some s].  All other fields delegate to [c].

| Parameter | Description |
|-----------|-------------|
| `s` | Label string surfaced in [decode_error.label] on errors. |
| `c` | The underlying codec. |

---

Combinator 21: satisfy_many0 — a zero-or-more run of bytes matching a predicate.
Decodes the maximal leading run of bytes satisfying [f] (stops at the first
rejected byte or end-of-input), returning the run as a [list byte].
The symbolic roundtrip holds under [wfcv xs == for_all f xs] and the framing
[rest_cond], [Seq.length r = 0 \/ not (f (Seq.index r 0))].  Alias: [many0].

| Parameter | Description |
|-----------|-------------|
| `f` | Predicate each run byte must satisfy. |

---

Combinator 22: satisfy_many1 — a one-or-more run of bytes matching a predicate.
Like [satisfy_many0] but requires a non-empty run ([wfcv] adds [Cons? xs]).
Alias: [many1].

| Parameter | Description |
|-----------|-------------|
| `f` | Predicate each run byte must satisfy. |

---

# Data.Codec.Pulse

Data.Codec.Pulse — C-extractable codec layer via Pulse + Custard.

Non-recursive leaf codecs (8 types) operating on `Pulse.Lib.Array.array`.
Each encode/decode function has a byte-level post-condition expressed as
Pulse separation logic.  The pure codec spec lives in `Data.Codec.Types`;
this module proves correspondence with it.  Written for F* v2026.09.20
(Custard `--custard_backend C`).

- `codec_t` — flat GADT: CT_Token, CT_ByteVal, CT_Uint8, CT_Word16BE,
  CT_Word32BE, CT_Word16LE, CT_Word32LE, CT_Varint
- `error_code_c` — C-compatible error codes
- `decode_result_c` — C-compatible decode result

Encoders (8), each a Pulse `fn` with a byte-level post-condition:
`encode_token`, `encode_byteval`, `encode_uint8`, `encode_word16be`,
`encode_word32be`, `encode_word16le`, `encode_word32le`, `encode_varint`;
dispatch via `encode_bytes`.

Decoders (8), each a Pulse `fn` returning `decode_result_c`:
`decode_token`, `decode_byteval`, `decode_uint8`, `decode_word16be`,
`decode_word32be`, `decode_word16le`, `decode_word32le`,
`decode_varint` (whose spec is the `noextract` `varint_decode_expected`).
Dispatch via `decode_bytes`.

Roundtrip lemmas (`lemma_pulse_roundtrip_*`) prove encode → decode
preserves values through the buffer; `lemma_pulse_encode_decode_match`
is the dispatch-level master lemma.

Public API stays `U32.t` for offsets/`pos`/`n`/`value` (matching the pure
spec + OCaml extraction); only the buffer read/write boundary converts to
`SizeT` via `uint32_to_sizet`.  `nosmt`/`noextract` spec helpers
`varint_encode_pred` and `varint_decode_expected` are not extracted.

---

# Data.Codec

Data.Codec — Derived combinators, operator aliases, and character predicates.
Re-exports every [Data.Codec.Types] symbol (all 22 combinators, plus
[one_of]/[take_until] helpers and every lemma) via [include].
Adds derived combinators built from the base set, backward-compat aliases,
byte and character classification predicates.
- 22 combinators: token, byte_val, satisfy, pure, text, bytes,
uint8, word16be, word16le, word32be, word32le, varint, digits_to_int,
custom, product, sum, map_, count, label, alt, satisfy_many0, satisfy_many1
- Ad-hoc helpers (not codecs): one_of, take_until (return triples)
- Derived combinators: choice, then_drop, drop_then, between, optional, take,
many0, many1
- Operator aliases: ( *> ), ( <* ), ( <|> )
- Character predicates: is_digit, is_upper, is_lower, is_alpha, is_alphanum,
is_space_or_tab, is_whitespace, is_printable (byte + char variants)
- Backward-compat aliases: word16_be, word32_be, word16_le, word32_le,
varint_codec, map, equiv_map, digits_to_integer, digits_to_int_alias
- Helper lemmas (lemma_*_helper, lemma_varint_*, lemma_bytes_*, lemma_digits_

---

Derived combinators

---

Derived Combinators

---

Combinator: choice — binary sum with unified type.
Implemented as [map_ (sum c1 c2)].
When both wfcv hold, c1 dominates (encodes via Inl path with tag [0x00]).
When only c2.wfcv holds, encodes via Inr path with tag [0x01].
When neither holds, [choice.enc x == Seq.empty] and [choice.wfcv x == false].
Callers should ensure wfcv sets are disjoint or accept c1-dominance.

| Parameter | Description |
|-----------|-------------|
| `c1` | First (preferred) codec. |
| `c2` | Second (fallback) codec. |

---

Lemma: when both wfcv hold, choice encodes via c1 (tag [0x00]).

---

Lemma: when only c2.wfcv holds, choice encodes via c2 (tag [0x01]).

---

Combinator: then_drop — parse c1 then c2, discard c1.
Alias: [( *> )].  Built from [product c1 c2] via [map_].

| Parameter | Description |
|-----------|-------------|
| `c1` | First codec (must be [codec unit]). |
| `c2` | Second codec. |

---

Combinator: drop_then — parse c1 then c2, discard c2.
Alias: [( <* )].  Built from [product c1 c2] via [map_].

| Parameter | Description |
|-----------|-------------|
| `c1` | First codec. |
| `c2` | Second codec (must be [codec unit]). |

---

Combinator: between — bracket a codec between open and close delimiters.
Equivalent to: [open_ *> c <* close].

| Parameter | Description |
|-----------|-------------|
| `open_` | Opening delimiter codec. |
| `close` | Closing delimiter codec. |
| `c` | The inner codec. |

---

Combinator: optional — tagged-union optional.
Encodes [Some x] as tag [0x00] followed by [c.enc x].
Encodes [None] as tag [0x01] followed by empty.
NOT backtracking — the tag byte disambiguates cases.
Built from [sum c (pure ())] via [map_].

| Parameter | Description |
|-----------|-------------|
| `c` | The inner codec. |

---

Combinator: take — exactly [n] bytes.

| Parameter | Description |
|-----------|-------------|
| `n` | Number of bytes to consume. Equivalent to [count n token]. |

---

Backward-compat alias for digits_to_int. Returns codec int, not codec nat.

---

char_to_byte: bridge from FStar.Char.char to UInt8.t.
(** Code points > 255 are truncated via % 256. Use char predicates only
(** on ASCII-range chars (code points < 128) to avoid silent corruption.
let char_to_byte (c: FStar.Char.char) : byte =
U8.uint_to_t (FStar.Char.int_of_char c % 256)
(** Character predicates — defined in terms of byte predicates via
(** char_to_byte bridge.
let char_is_digit (c: FStar.Char.char) : bool =
is_digit (char_to_byte c)
(** True if char is an ASCII uppercase letter.

---

Satisfy combinator on is_digit. Encodes/decodes a single digit byte.

---


*Generated from fsdoc comments in source files.*
