/* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later */

/**
 * bench-ref.c — the **hand-written C baseline** for the codec's 8 wire formats.

 * @header bench-ref

 * This file is what "close to hand-written C" is measured *against*
 * (`REQ-ISO-C-PERF`; `REQ-ISO-GOAL`'s "fast in C" conjunct).  It is written
 * the way a C programmer writes a binary reader/writer, not as a transcription
 * of the F* definitions:

 *   - the wire is LEB128 for `varint` and fixed-width for the rest;
 *   - a decoder returns a small struct (`tag` + `n` + `value`), the same shape
 *     the extracted C returns, so the comparison is about *generated code* and
 *     not about API shape;
 *   - the same message, the same op list, the same iteration count and the same
 *     clock as `bench-pulse.c`.

 * Nothing here includes the extracted header.  The baseline is independent by
 * construction.

 * The message is a fixed 16-byte, 7-field record, written once (`g_msg`) and
 * reused by every row, so a field's offset cannot differ between rows.
 */

#include "bench.h"

/* The sink is `volatile`: a plain global is provably written and never read,
   which lets the optimiser delete the stores that make an op observable. */
volatile uint64_t g_sink = 0;

/* ── Baseline wire layer ─────────────────────────────────────────── */

/* The baseline's own codec tag — the same 8 formats, in the same order as the
   extracted `codec_t`, so a row can be read across the two drivers. */
enum bcodec {
    B_TOKEN, B_BYTEVAL, B_UINT8, B_WORD16BE,
    B_WORD32BE, B_WORD16LE, B_WORD32LE, B_VARINT
};

#define B_INL 0
#define B_INR 1

typedef struct { int tag; uint32_t n, value; } bresult;

static inline bresult b_ok(uint32_t n, uint32_t v)
{
    bresult r = { B_INR, n, v };
    return r;
}
static inline bresult b_err(uint32_t pos)
{
    bresult r = { B_INL, pos, 0 };
    return r;
}

static inline uint32_t b_enc(uint32_t c, uint32_t v, uint8_t *b, uint32_t i)
{
    switch (c) {
    case B_TOKEN:
    case B_UINT8:
        b[i] = (uint8_t)v;
        return 1;
    case B_BYTEVAL:
        b[i] = (uint8_t)v;          /* not in the op list; kept for parity */
        return 1;
    case B_WORD16BE:
        b[i] = (uint8_t)(v >> 8);
        b[i + 1] = (uint8_t)v;
        return 2;
    case B_WORD16LE:
        b[i] = (uint8_t)v;
        b[i + 1] = (uint8_t)(v >> 8);
        return 2;
    case B_WORD32BE:
        b[i] = (uint8_t)(v >> 24);
        b[i + 1] = (uint8_t)(v >> 16);
        b[i + 2] = (uint8_t)(v >> 8);
        b[i + 3] = (uint8_t)v;
        return 4;
    case B_WORD32LE:
        b[i] = (uint8_t)v;
        b[i + 1] = (uint8_t)(v >> 8);
        b[i + 2] = (uint8_t)(v >> 16);
        b[i + 3] = (uint8_t)(v >> 24);
        return 4;
    default: { /* B_VARINT */
        uint8_t *p = b + i;
        uint32_t n = 0;
        while (v >= 128) {
            *p++ = (uint8_t)((v & 0x7f) | 0x80);
            v >>= 7;
            n++;
        }
        *p = (uint8_t)v;
        return n + 1;
    }
    }
}

static inline bresult b_dec(uint32_t c, const uint8_t *b, uint32_t i, uint32_t n)
{
    if (n < 1) return b_err(i);
    switch (c) {
    case B_TOKEN:
    case B_UINT8:
        return b_ok(1, b[i]);
    case B_BYTEVAL:
        return b_ok(1, 0);
    case B_WORD16BE:
        if (n < 2) return b_err(i);
        return b_ok(2, ((uint32_t)b[i] << 8) | b[i + 1]);
    case B_WORD16LE:
        if (n < 2) return b_err(i);
        return b_ok(2, b[i] | ((uint32_t)b[i + 1] << 8));
    case B_WORD32BE:
        if (n < 4) return b_err(i);
        return b_ok(4, ((uint32_t)b[i] << 24) | ((uint32_t)b[i + 1] << 16) |
                       ((uint32_t)b[i + 2] << 8) | b[i + 3]);
    case B_WORD32LE:
        if (n < 4) return b_err(i);
        return b_ok(4, b[i] | ((uint32_t)b[i + 1] << 8) |
                       ((uint32_t)b[i + 2] << 16) | ((uint32_t)b[i + 3] << 24));
    default: { /* B_VARINT — the canonical reader: rejects a group-zero stop. */
        uint32_t v = 0, shift = 0, k = 0;
        for (;;) {
            if (k >= n || k >= 5) return b_err(i);
            uint8_t byte = b[i + k];
            uint32_t group = byte & 0x7f;
            if (shift == 28 && group > 15) return b_err(i);
            v |= group << shift;
            k++;
            if (byte < 128) {
                if (k > 1 && group == 0) return b_err(i);
                return b_ok(k, v);
            }
            shift += 7;
        }
    }
    }
}

/* ── The op list — identical in both drivers ─────────────────────── */

#define MSG_LEN 16

/* The 7-field message: token, u8, u16be, u32be, u16le, u32le, varint(130). */
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

static const uint32_t g_codec[7] = {
    B_TOKEN, B_UINT8, B_WORD16BE, B_WORD32BE, B_WORD16LE, B_WORD32LE, B_VARINT
};
static const uint32_t g_val[7] = {
    'X', 0x2a, 0x1234, 0xdeadbeefu, 0x1234, 0xdeadbeefu, 130u
};
/* The varint encoder's four widths (1, 2, 3, 4/5-byte boundaries). */
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
    for (int k = 0; k < 6; k++) *acc += b_enc(g_codec[k], g_val[k], g_buf, g_off[k]);
}

static void op_encode_varint(void *ctx)
{
    uint64_t *acc = ctx;
    for (int k = 0; k < 4; k++) *acc += b_enc(B_VARINT, g_vvals[k], g_buf, 0);
}

static void op_encode_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t off = 0;
    for (int k = 0; k < 7; k++) off += b_enc(g_codec[k], g_val[k], g_buf, off);
    *acc += off;
}

static void op_decode_leaves(void *ctx)
{
    uint64_t *acc = ctx;
    for (int k = 0; k < 6; k++) *acc += b_dec(g_codec[k], g_msg, g_off[k], g_len[k]).value;
}

static void op_decode_varint(void *ctx)
{
    uint64_t *acc = ctx;
    *acc += b_dec(B_VARINT, g_msg, 14, 2).value;
}

static void op_decode_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t pos = 0;
    for (int k = 0; k < 7; k++) {
        bresult r = b_dec(g_codec[k], g_msg, g_off[k], g_len[k]);
        pos = r.n;
        *acc += r.value;
    }
    *acc += pos;
}

static void op_roundtrip_message(void *ctx)
{
    uint64_t *acc = ctx;
    uint32_t off = 0;
    for (int k = 0; k < 7; k++) off += b_enc(g_codec[k], g_val[k], g_buf, off);
    *acc += off;
    off = 0;
    for (int k = 0; k < 7; k++) {
        bresult r = b_dec(g_codec[k], g_buf, off, off < MSG_LEN ? MSG_LEN - off : 0);
        off = r.n;
        *acc += r.value;
    }
}

/* ── Main ────────────────────────────────────────────────────────── */

int main(void)
{
    uint64_t acc = 0;

    /* Correctness first: the baseline must round-trip the message before its
       timings mean anything.  A benchmark of a wrong code is a wrong number. */
    {
        uint8_t tmp[MSG_LEN];
        uint32_t off = 0;
        for (int k = 0; k < 7; k++) off += b_enc(g_codec[k], g_val[k], tmp, off);
        if (off != MSG_LEN || memcmp(tmp, g_msg, MSG_LEN) != 0) {
            fprintf(stderr, "baseline: FAIL — encoded bytes differ from g_msg\n");
            return 1;
        }
        for (int k = 0; k < 7; k++) {
            bresult r = b_dec(g_codec[k], tmp, g_off[k], g_len[k]);
            if (r.tag != B_INR || r.n != g_len[k] || r.value != g_val[k]) {
                fprintf(stderr, "baseline: FAIL — field %d did not round-trip\n", k);
                return 1;
            }
        }
        fprintf(stderr, "baseline: roundtrip OK (7 fields, %d bytes)\n", MSG_LEN);
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
    fprintf(stderr, "baseline: sink=%llu\n", (unsigned long long)g_sink);
    return 0;
}
