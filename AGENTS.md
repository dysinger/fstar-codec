# fstar-codec — Agent Guide & Handoff

`Data.Codec` — verified bidirectional codec library, extracted from the xeno
monorepo (`codec/`) as a standalone repo.  F* source is 0-admit.  This file
records session state and the unfinished Pulse-port work so the next session
resumes cleanly.

## ⛔ MANDATES (binding — read before doing anything)

1. **NEVER run `fstar.exe`, `nix build`, `make`, or any verification/extraction
   step in the foreground.**  They can hang forever (observed: the Pulse
   verify of `Data.Codec.Pulse` sleeps at 0% CPU for 35+ minutes — a non-terminating
   Z3/Pulse query).  **Always** wrap them with a hard timeout so a stuck
   process dies and you regain control:

   ```bash
   # macOS mkdir -p /tmp/x; time
   timeout 600 fstar.exe ... || echo "TIMED OUT (exit $?)"
   # or, portably, for a nix build:
   nix build ... & pid=$!; ( sleep 900 && kill -9 $pid ) & guard=$!; wait $pid; kill $guard 2>/dev/null
   ```

   Choose a per-step budget (fstar verify ≤ 10 min, `nix build` ≤ 15 min) and
   **kill anything that exceeds it** rather than letting it sit.  10% of
   launched builds silently hang; treat a 0%-CPU `fstar.exe`/`nix` process as
   stuck, not "still working".

2. **Do not batch-verify multiple `fstar.exe` invocations without a timeout on
   each.**  A hang in one module blocks everything downstream forever.

3. **A hang is a bug to diagnose, not a patience exercise.**  A stopped (`S`,
   0% CPU) `fstar.exe` mid-verify is almost always a non-terminating SMT query
   in a Pulse `fn` (typically a post-condition that SMT can't discharge and
   keeps exploring).  Capture *which* module/query and move on — see the
   diagnosis in the next-session note below.

## ✅ RESOLVED: `Data.Codec.Pulse` verification hang (FIXED two sessions ago)

> **Canonical record**: [`openspec/changes/diagnose-pulse-hang/tasks.md`](openspec/changes/diagnose-pulse-hang/tasks.md)
> (and [`proposal.md`](openspec/changes/diagnose-pulse-hang/proposal.md)).
>
> ### FIXED — `Data.Codec.Pulse` verify was a varint-roundtrip SMT hang

**Root cause (bisected):** `lemma_pulse_roundtrip_varint` is a **non-terminating
SMT query** — not the word32 lemmas (those are *slow* ~90s but terminate), and
not `encode_*`/`decode_*` (the encoders/decoders/dispatchers all verify green in
~30s).  Z3 spins at **100% CPU forever** (not the older 0%-`stopped` symptom);
raising `--z3rlimit` 80 → 120 → 800 does **not** help.

The `varint` roundtrip is hard because `encode_varint`/`decode_varint` are
**hand-inlined** (not the pure `varint.enc`/`.dec` projections), so the
roundtrip `fn`'s single SMT query must discharge the 5-way threshold split
(`<128`/`<16384`/`<2097152`/`<268435456`/else) through nested `%128`/`/128`
extraction **and** U32 `add`/`mul` reconstruction — a query Z3 never decides.

**Fix (landed, 0-admit):** added a pure `noextract` `Lemma`
`lemma_varint_roundtrip_smtpat` with an
`[SMTPat (varint_decode_expected i (U32.uint_to_t (nbytes_of_varint (U32.v v))) s)]`
trigger in `src/Data.Codec.Pulse.fst`.  Its body does an explicit 5-way case
split over the **existing** `DC.lemma_varint_{2,3,4,5}byte_arithmetic`
identities, lifting the div/mod decomposition into head-normal form.  The
trigger fires where the roundtrip `fn`'s term (`varint_decode_expected i m s1`,
`U32.v m == nbytes_of_varint (U32.v v)`) unifies `m` to the `uint_to_t` form.

**Verified GREEN end-to-end:**
- `make check` / direct verify loop (Types → Codec → Pulse → 3 test modules,
  `--z3rlimit 120`): all six modules
  "All verification conditions discharged successfully", 0-admit.
- `nix build .#native .#ocaml .#fsharp` + `nix flake check` — all GREEN.

T3.2/T3.3 (test rewrite) is now **DONE** — the leaf AND the three test modules
all verify; `TST_MODS` is populated.

## Current state (post Pulse port)

### GREEN (verified this session, F* `v2026.09.20+lsp`)

Full gate verified GREEN at 0-admit (`--z3rlimit 80`):

- `Data.Codec.Types` + `Data.Codec` + `Data.Codec.Pulse` + the three test
  modules (`Data.Codec.Test.Roundtrip` + `Integration` + `Pulse`).
- `nix build .#fstar-codec-checked` — 0 admits (spec + Pulse leaf + tests).
- `nix build .#fstar-codec-ocaml` — pure spec to OCaml findlib (`fstar_codec`).
- `nix build .#fstar-codec-native` — the Pulse leaf extracted to C11 via
  Custard, `libfstar-codec.{dylib,so,a}` + `fstar_codec.h`, no karamel
  (produced `dylib`/`a` once; now blocked by the hang).

### `Data.Codec.Pulse` is PORTED to Pulse (this session)

The ~860-line Pulse rewrite is complete and 0-admit: 8 encoders + 8 decoders +
`encode_bytes`/`decode_bytes` dispatch + `varint_encode_pred`/
`varint_decode_expected` (`noextract` pure specs) + 8 roundtrip lemmas +
`lemma_pulse_encode_decode_match`.  Extracts to warning-free C11.  The port was
much easier than the proposal feared: the pure `codec` `.enc`/`.dec` are record
projections that compute, so `dec (enc x)` reduces and SMT discharges the
roundtrip lemmas automatically (the old `lemma_word32_shift_bytes` /
`FStar.HyperStack.ST.get ()` `h_mid` heap threading is GONE, not ported).

### Remaining work (DONE — T3.2 + T3.3 landed)

The two test modules are now Pulse-portable and re-added to `TST_MODS` (the
full gate — 3 src + 3 test modules — verifies GREEN at 0-admit).  Two notes:

- `test/Data.Codec.Test.Roundtrip.fst` — the 110 pure tests stay in this
  **non**-Pulse module; the 10 buffer roundtrip tests moved to a **new**
  `test/Data.Codec.Test.Pulse.fst` (`#lang-pulse`), because Pulse reserves the
  `label` keyword which the pure tests use as a combinator + record field.
- `test/Data.Codec.Test.Integration.fst` — dropped the dead `_pulseL0`…`_pulseL8`
  anchors (pre-roll-forward helper lemmas) and re-anchored the stack tests.

See [`openspec/changes/low-pulse-port/tasks.md`](openspec/changes/low-pulse-port/tasks.md)
T3.2/T3.3 for the full detail.

## The old KaRaMeL/Low\* layer is DEAD (and the leaf is now PORTED)

F* `v2026.09.20` **removed the entire Low\*/KaRaMeL stdlib**: the namespaces
`FStar.HyperStack`, `FStar.HyperStack.ST`, and `LowStar.Buffer` no longer
exist.  Consequently the **old** `src/Data.Codec.Pulse.fst` could not typecheck
and was ported to Pulse this session (see "PORTED" above).  The test modules
too were ported/rewritten (the 10 buffer tests now live in a dedicated
`#lang-pulse` `Data.Codec.Test.Pulse` module) — nothing references the dead
Low*/Stack namespaces anymore.

The `krml` / `native` / `rust` / `wasm` targets were deleted along with the
KaRaMeL toolchain.  The only C-extraction path in the new F\* is **Custard**
(`--codegen Custard --custard_backend C`), and Custard extracts **Pulse**
(`fn`, `Pulse.Lib.Reference`/`Vec`/`Array`), not the old Low\* style.

## Roll-forward drift fixes (already landed, 0-admit preserved)

`src/Data.Codec.Types.fst` needed three upstream removals:

1. `open FStar.Mul` removed (module deleted; `*` is now natively multiplication).
2. `Prims.op_Multiply a 10` → `a * 10` (6 sites; `op_Multiply` deleted from `Prims`).
3. `--split_queries always` removed from two `#push-options` (option deleted;
   F* now emits one SMT query per proof obligation).

`default.nix` `ocaml` backend needed two fixes:

4. `--codegen OCaml` now requires **one source file per invocation** (Error 10).
5. OCaml extraction needs the dependencies' `.checked` files loaded — the
   `ocaml-src` derivation now verifies in dependency order (`--cache_checked_modules
   --cache_dir cache`) then extracts with `--include cache`.

flake.nix wiring (mirrors upstream `../fstar/flake.nix`):

- `ocamlPackages = ocaml-ng.ocamlPackages_5_3` (5.3, NOT 5.4 — `v2026.09.20`
  uses 5.3; 5.4 was only the fork's `t/ocaml-5.4` TopGit branch).
- `karamel` is **fully removed** — it is an in-tree git submodule of F\* that
  `.nix/fstar.nix` synthesizes only to install the `krml` binary + headers,
  which we do not consume.  The flake passes `karamel-src = emptyDirectory`
  + `karamelOcamlDeps = []` and sets `FSTAR_USE_KRML_EXE=1` with a no-op
  `karamel/Makefile` stub so the unconditional `make -C karamel install` is
  a NOP.  The installed F\* now ships only `fstar.exe` (no krml).
- The `fstar` derivation is overridden with
  `buildPhase = make OTHERFLAGS='--z3rlimit 20 --retry 3'` — the default
  rlimit (5) makes the 4-stage bootstrap's `FStar.Math.Fermat.binomial_theorem`
  deterministically time out (Error 19) under z3 4.13.3.  `OTHERFLAGS` flows
  into the nested `make -f mk/lib.mk` (the `.alib2.src.touch` recipe does not
  re-specify it, unlike `fsharp-lib.src`).

## Backend matrix (post roll-forward, post fsdoc-finalize)

All four targets GREEN, verified this session via the real nix gate:

| Backend | Mechanism | Status |
|---|---|---|
| `ocaml` | `--codegen OCaml` (legacy ML) | ✅ GREEN (findlib `codec-ocaml`) |
| `native` (C) | `--custard_backend C` (direct C11, no karamel) | ✅ GREEN (`libcodec.{dylib,a}` + `codec.h`) |
| `fsharp` | `--codegen FSharp` / `--custard_backend FSharp` | ✅ GREEN (`.NET 10` SDK, `Custard.dll`, 0 warn/err) |
| `checked` | F\* verify gate | ✅ GREEN (0-admit, 3 src + 3 test) |
| `rust` | `--custard_backend KrmlRust` → karamel | ❌ dead upstream (431 rustc errors, no `lowstar` module) |
| `wasm` | — | ❌ gone — no wasm backend in the new F\* |

Custard's `--custard_backend` enum is exactly `["OCaml"; "FSharp"; "KrmlC";
"KrmlRust"; "C"]`.  There is no wasm anywhere.  `native`, `ocaml`, and
`fsharp` are all GREEN; `rust`/`wasm` are dropped permanently.

## Pulse idiom (pinned by the spike, applied to the leaf)

`spike/Data.Codec.Spike.fst` (gitignored) was the Phase-1 spike; the exact
idiom is now applied in `src/Data.Codec.Pulse.fst`.  Key facts:

- **Buffer type**: `A.array U8.t` (`Pulse.Lib.Array`), view `A.pts_to b s`
  (`s : Seq.seq U8.t` erased).  Read `b.(j)`, write `b.(j) <- x` with `j :
  SizeT.t`; convert `U32.t` offsets with `US.uint32_to_sizet`.
- **Public API stays `U32.t`** (matching the pure spec + OCaml extraction).
- **Bounds live in TYPES/refinements, not `pure` preconds** — a `pure (...)`
  fact in `requires` is NOT visible in the `ensures`; use `A.length b` (pure
  `Ghost nat`) for self-contained bounds and re-assert `A.length b ==
  Seq.length s` in the `pure`.
- **No `U32.v`/`U8.v`/nat `%` in extracted bodies** (Error 368): use
  `FStar.Int.Cast.uint32_to_uint8` / `uint8_to_uint32`.
- **`U32.add i k` needs `U32.v i + k < 4294967296`** in `requires`.
- **word32be/le use `U32.div` (not shift)** to match the pure `*.enc`
  division structure (avoids `lemma_word32_shift_bytes`).
- **`noextract`** on `varint_encode_pred`/`varint_decode_expected` keeps
  Custard from rooting them (they use `Seq`/`Prims.int`, which C can't emit).
- **Declaration order is SMT-sensitive — varint MUST stay LAST.**
  `encode_varint`/`varint_encode_pred` (and `decode_varint`/
  `varint_decode_expected`) must come **after** the word16/word32 encoders,
  not alphabetically among them.  Moving them earlier puts the 5-way varint
  case-split in scope *before* `lemma_pulse_roundtrip_word32be`, tipping that
  already-fragile word32 SMT query from "slow (~90s)" into a non-terminating
  z3 spin (100% CPU).  Likewise `lemma_varint_roundtrip_smtpat` must sit after
  `lemma_pulse_roundtrip_word32le` (its SMTPat trigger pollutes the word-lemma
  queries) and immediately before `lemma_pulse_roundtrip_varint` (dependency).
  The canonical order (verified 0-admit) is: byteval, token, uint8,
  word16be, word16le, word32be, word32le, varint(-pred/-spec), then smtpat,
  varint-roundtrip, encode_decode_match.

## Definition of done

**DONE** — the repo is fully ported to F\* `v2026.09.20` and the complete gate
is GREEN at 0-admit.  This session (the `pulse-fsdoc-finalize` change) landed:

- `Data.Codec.Pulse` regrouped into alphabetical groups (with the
  **varint-last** SMT-safe ordering — see "Pulse idiom" above) and fully
  fsdoc'd.
- `Data.Codec.Types` + `Data.Codec` fsdoc-audited (every public decl carries
  `(** … *)`).
- Real nix gate run end-to-end: `nix build .#native .#ocaml .#fsharp` +
  `nix flake check` (incl. `.#formatting`) + `nix develop && make check` —
  **all GREEN**.

No further functional work remains.  The only open openspec items are
bookkeeping (ticking done boxes, archiving dead changes) — see the task files.

## Build commands

```bash
nix build .#checked   # verification gate (0-admit, spec + Pulse leaf + tests)
nix build .#ocaml     # OCaml findlib package (pure spec + Pulse leaf)
nix build .#native    # C11 shared/static lib of the Pulse leaf (default)
nix build .#fsharp    # .NET library
nix develop && make check   # dev loop (no nix)
```
