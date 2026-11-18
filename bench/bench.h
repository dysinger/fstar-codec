/* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later */

/**
 * bench.h — the timing primitives shared by both benchmark drivers.

 * @header bench.h

 * Two drivers include this file:
 *   - `bench-ref.c` — a **hand-written C baseline** for the same 8 wire
 *     formats.  It does NOT include the extracted code.
 *   - `bench-pulse.c` — the **extracted C**, from `codec.h` (Custard's
 *     `Custard.h`), calling `encode_bytes` / `decode_bytes`.

 * Both use the same buffer, the same iteration count and the same clock, so
 * the two figures are comparable.  The baseline is compiled from this file
 * only; nothing here sees the F* type definitions.

 * The only thing this file adds beyond `<time.h>` is:
 *   - `now_ns()` — a monotonic nanosecond clock;
 *   - `g_sink` — an accumulator the compiler cannot fold away (a benchmark
 *     whose result is unused is a benchmark of the optimiser).
 */

#ifndef BENCH_H
#define BENCH_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/** Host-wide accumulator.  Every driver writes its results here; `main`
    prints one digest byte at the end so the work cannot be dead-coded. */
extern volatile uint64_t g_sink;

/** Monotonic nanoseconds.  On Darwin `CLOCK_MONOTONIC`; elsewhere the same
    clock glibc exposes under the same name. */
static inline uint64_t now_ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000000000ull + (uint64_t)t.tv_nsec;
}

/** Number of timed rounds.  The **median** is printed and the **best** is
    also available, so a scheduler hiccup cannot move the number.  Override
    with `-DBENCH_ROUNDS=n`. */
#ifndef BENCH_ROUNDS
#define BENCH_ROUNDS 11
#endif

/** Iterations per round.  Must stay large enough that one round spans many
    clock ticks — see the note on resolution below.  Override with
    `-DBENCH_ITERS=n`. */
#ifndef BENCH_ITERS
#define BENCH_ITERS 1000000
#endif

/** Repeats of one op per timed loop (amortises the clock read).
    Override with `-DBENCH_BURST=n`. */
#ifndef BENCH_BURST
#define BENCH_BURST 64
#endif

/** Compare for `qsort` — ascending `uint64_t`. */
static inline int cmp_u64(const void *a, const void *b)
{
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

/** One timed operation: a function pointer plus its opaque context.

    The op does **one** unit of work and takes no per-iteration argument.  The
    unit's cost is what the harness reports; that is why a row's name carries
    its batch size (`encode/leaves (x6)` — six leaf encodes per call).  Giving
    each iteration its own input is what makes the optimiser able to delete the
    work: a vary-the-input guard costs ~1.2 ns, which is itself larger than most
    of the ops here.  A fixed input and a `volatile` sink is the honest pair. */
typedef void (*bench_op)(void *ctx);

/* ── Resolution: the number this harness can and cannot resolve ────

   `CLOCK_MONOTONIC` on this host (and on Darwin generally) reports whole
   microseconds — `clock_getres` returns 1000 ns.  A per-call read therefore
   floors every op below ~1 us to 0, which is how a naive harness reports
   "0 ns/op" for everything.

   The cure is arithmetic, not a better clock: one round does BENCH_ITERS
   calls and is timed once, so the round's total is hundreds of microseconds
   and the *division* carries the resolution.  The result is kept in
   **picoseconds** (`uint64_t` ps, integer) so nothing is floored in between;
   the printed column is `ns_x1000`, i.e. ns with three decimals.

   The floor of the harness itself — one indirect call through the op pointer
   plus its argument store, with the op body empty — is measured by the
   `bench-floor` target and printed in the same units as every other row, so a
   row can be compared against it.  A row within ~2x the floor is reported as
   "at the floor" by `bench/run.sh`, not as a throughput figure.            */

/** Picoseconds per op, one round. */
static inline uint64_t bench_time_ps(bench_op op, void *ctx)
{
    uint64_t bursts = (uint64_t)BENCH_ITERS / (uint64_t)BENCH_BURST;
    uint64_t calls = bursts * (uint64_t)BENCH_BURST;
    /* `volatile` on the pointer is what stops the optimiser proving it knows
       the callee for the whole loop.  Note what it does NOT fix: hoisting a
       single call out of the loop.  Measured — with `vop` the indirect call
       and its body remain very much alive (the floor row is nonzero and grows
       with `BENCH_BURST`), but a fully loop-invariant call is still hoisted
       once, so a row that will not grow with `BENCH_BURST` is suspected of
       hoisting and is checked, not trusted.  Making the input a function of
       the iteration defeats hoisting and costs more than the ops here; see the
       typedef comment above. */
    bench_op volatile vop = op;
    uint64_t t0 = now_ns();
    for (uint64_t i = 0; i < bursts; i++) {
        for (int bb = 0; bb < BENCH_BURST; bb++) vop(ctx);
    }
    uint64_t t1 = now_ns();
    /* ns -> ps is *1000; divide by the call count afterwards so the integer
       division carries all of the round's resolution. */
    uint64_t ps = (t1 - t0) * 1000ull / calls;
    /* A round whose total is under a few clock ticks is not a measurement; say
       so rather than let the caller print a number that came from rounding. */
    if (t1 - t0 < 4) return 0;   /* 0 == "unresolved", see bench_time() */
    return ps;
}

/** Median and best ps/op over `BENCH_ROUNDS` rounds. */
typedef struct { uint64_t median_ps, best_ps; int unresolved; } bench_stat;

static inline bench_stat bench_time(bench_op op, void *ctx)
{
    uint64_t s[BENCH_ROUNDS];
    for (int r = 0; r < BENCH_ROUNDS; r++) s[r] = bench_time_ps(op, ctx);
    qsort(s, BENCH_ROUNDS, sizeof(uint64_t), cmp_u64);
    bench_stat st;
    st.median_ps = s[BENCH_ROUNDS / 2];
    st.best_ps = s[0];
    /* Count unresolved rounds explicitly so the totals line can refuse to
       average them in. */
    st.unresolved = 0;
    for (int r = 0; r < BENCH_ROUNDS; r++) if (s[r] == 0) st.unresolved++;
    return st;
}

/** Print one result row: `label<TAB>median_ps<TAB>best_ps`. */
#define BENCH_ROW(label, st) \
    printf("%s\t%llu\t%llu\t%d\n", (label), \
           (unsigned long long)((st).median_ps), (unsigned long long)((st).best_ps), \
           (st).unresolved)

/** Print a header naming the columns. */
#define BENCH_HEADER() printf("# row\tmedian_ps\tbest_ps\tunresolved_rounds\n")

#endif /* BENCH_H */
