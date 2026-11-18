/* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later */

/**
 * bench-pulse.c — the **extracted C** driver for the codec's 8 wire formats.

 * @header bench-pulse

 * This driver calls the C that F* extracted from `Data.Codec.Pulse`
 * (`Custard.c`, linked as `libcodec`), through the public header `codec.h`.
 * The message, the op list, the field offsets and the iteration count are
 * **identical** to `bench-ref.c`'s; only who wrote the wire layer differs.

 * The extracted layer is slightly more general than the baseline: `encode_bytes`
 * and `decode_bytes` dispatch on a `codec_t` tag, so the measurement includes
 * that tag comparison.  That *is* the artifact's real call shape (`[D11]`), so
 * it is the honest thing to measure — and it means a fast result here is a fast
 * result for the shipped API, not for a wrapper written to look good.

 * `codec_t` is passed by value (a small struct: a tag plus a union) and
 * `decode_result_c` is returned by value, exactly as the header declares.
 */

#include "bench.h"
#include "codec.h"

/* The sink is `volatile`: a plain global is provably written and never read,
   which lets the optimiser delete the stores that make an op observable. */
volatile uint64_t g_sink = 0;

/* ── The op list — identical to bench-ref.c ──────────────────────── */

#define MSG_LEN 16

static const uint8_t g_msg[MSG_LEN] = {
    'X',                    /* token            @ 0, len 1 */
    0x2a,                   /* uint8            @ 1, len 1 */
    0x12, 0x34,             /* word16be         @ 2, len 2 */
    0xde, 0xad, 0xbe, 0xef, /* word32be         @ 4, len 4 */
    0x34, 0x12,             /* word16le         @ 8, len 2 */
    0xef, 0xbe, 0xad, 0xde, /* word32le         @10, len 4 */
    0x82, 0x01              /* varint = 130     @14, len 2 */
};

static const uint32_t g_off[7] = { 0, 1, 2, 4, 8, 10, 14 };
static const uint32_t g_len[7] = { 1, 1, 2, 4, 2, 4,  2  };

static const codec_t g_codec[7] = {
    { .tag = CT_TOKEN },
    { .tag = CT_UINT8 },
    { .tag = CT_WORD16BE },
    { .tag = CT_WORD32BE },
    { .tag = CT_WORD16LE },
    { .tag = CT_WORD32LE },
    { .tag = CT_VARINT }
};
static const uint32_t g_val[7] = {
    'X', 0x2a, 0x1234, 0xdeadbeefu, 0x1234, 0xdeadbeefu, 130u
};
static const uint32_t g_vvals[4] = { 130u, 16384u, 2097152u, 268435456u };

static uint8_t g_buf[MSG_LEN];

/* ── The ops ─────────────────────────────────────────────────────── */

/* The harness's own floor: one indirect call through the op pointer and its
   argument store, with an empty body.  Every row is compared against this, so
   a row at the floor is reported as a floor, not as a throughput figure. */
static void op_floor(void *ctx)
{
    (void)ctx;
}

static void op_encode_leaves(void *ctx)
{
    uint64_t *acc = ctx;
    for (int k = 0; k < 6; k++)
        *acc += encode_bytes(g_codec[k], g_val[k], g_buf, g_off[k]);
}

static void op_encode_varint(void *ctx)
{
    uint64_t *acc = ctx;
    for (int k = 0; k < 4; k++)
        *acc += encode_bytes(g_codec[6], g_vvals[k], g_buf, 0);
}

static void op_encode_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t off = 0;
    for (int k = 0; k < 7; k++) off += encode_bytes(g_codec[k], g_val[k], g_buf, off);
    *acc += off;
}

static void op_decode_leaves(void *ctx)
{
    uint64_t *acc = ctx;
    for (int k = 0; k < 6; k++)
        *acc += decode_bytes(g_codec[k], (uint8_t *)g_msg, g_off[k], g_len[k]).val.DR_Inr.value;
}

/* The row T9.2 reads: the canonicalisation's guard sits on this path. */
static void op_decode_varint(void *ctx)
{
    uint64_t *acc = ctx;
    *acc += decode_bytes(g_codec[6], (uint8_t *)g_msg, 14, 2).val.DR_Inr.value;
}

static void op_decode_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t pos = 0;
    for (int k = 0; k < 7; k++) {
        decode_result_c r = decode_bytes(g_codec[k], (uint8_t *)g_msg, g_off[k], g_len[k]);
        pos = r.val.DR_Inr.n;
        *acc += r.val.DR_Inr.value;
    }
    *acc += pos;
}

static void op_roundtrip_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t off = 0;
    for (int k = 0; k < 7; k++) off += encode_bytes(g_codec[k], g_val[k], g_buf, off);
    *acc += off;
    off = 0;
    for (int k = 0; k < 7; k++) {
        decode_result_c r = decode_bytes(g_codec[k], g_buf, off,
                                         off < MSG_LEN ? MSG_LEN - off : 0);
        off = r.val.DR_Inr.n;
        *acc += r.val.DR_Inr.value;
    }
}

/* ── Main ────────────────────────────────────────────────────────── */

int main(void)
{
    uint64_t acc = 0;

    /* Correctness first: the extracted C must encode the SAME bytes as the
       baseline before a timing means anything.  This also catches the case
       where the wrong `codec_t` tag is paired with a field. */
    {
        uint8_t tmp[MSG_LEN];
        uint32_t off = 0;
        for (int k = 0; k < 7; k++) off += encode_bytes(g_codec[k], g_val[k], tmp, off);
        if (off != MSG_LEN || memcmp(tmp, g_msg, MSG_LEN) != 0) {
            fprintf(stderr, "pulse: FAIL — encoded bytes differ from g_msg\n");
            return 1;
        }
        for (int k = 0; k < 7; k++) {
            decode_result_c r = decode_bytes(g_codec[k], tmp, g_off[k], g_len[k]);
            if (r.tag != DR_INR || r.val.DR_Inr.n != g_len[k] || r.val.DR_Inr.value != g_val[k]) {
                fprintf(stderr, "pulse: FAIL — field %d did not round-trip\n", k);
                return 1;
            }
        }
        fprintf(stderr, "pulse: roundtrip OK (7 fields, %d bytes)\n", MSG_LEN);
    }

    BENCH_HEADER();
    BENCH_ROW("floor/indirect-call (x1)", bench_time(op_floor, &acc));
    BENCH_ROW("encode/leaves (x6)",    bench_time(op_encode_leaves,    &acc));
    BENCH_ROW("encode/varint (x4)",    bench_time(op_encode_varint,    &acc));
    BENCH_ROW("encode/message (x7)",   bench_time(op_encode_message,   &acc));
    BENCH_ROW("decode/leaves (x6)",    bench_time(op_decode_leaves,    &acc));
    BENCH_ROW("decode/varint (x1)",    bench_time(op_decode_varint,    &acc));
    BENCH_ROW("decode/message (x7)",   bench_time(op_decode_message,   &acc));
    BENCH_ROW("roundtrip/message (x7)", bench_time(op_roundtrip_message, &acc));

    g_sink = acc;
    fprintf(stderr, "pulse: sink=%llu\n", (unsigned long long)g_sink);
    return 0;
}
