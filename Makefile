# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# F* dev-loop build (verify).
#
# Usage: nix develop, then `make check`.
#
# FSTAR_CHECKED is exported by the flake devShell (see flake.nix shellHook).
# Override it here if needed.

# ── Tools ──────────────────────────────────────────────────────────

# Build output directory.  Defaults to `./out` for the dev loop; nix
# derivations (default.nix) override it to `$out` so the Makefile writes
# straight into the nix store output path.
OUT ?= out

FSTAR ?= fstar.exe

ULIB := $(shell $(FSTAR) --locate_lib 2>/dev/null || echo /none)/ulib

# Pulse ships in the install under $(locate_lib)/pulse (sources under
# pulse/{common,pulse/lib}, `.checked` under pulse/{common.checked,
# pulse.checked}).  Data.Codec.Pulse (in Pulse) needs these, since FSTAR_FLAGS
# uses --no_default_includes.
FLIB := $(shell $(FSTAR) --locate_lib 2>/dev/null || echo /none)
PULSE_DIRS := $(FLIB)/pulse/common\
  $(FLIB)/pulse/common.checked\
  $(FLIB)/pulse/pulse/lib\
  $(FLIB)/pulse/pulse.checked

# Warning 274 (namespace "X.Pulse" shadows upstream "Pulse") is benign noise;
# silence it.  See the --warn_error -274 flag below.

FSTAR_FLAGS = --no_default_includes --warn_error -274 \
  --include $(ULIB) \
  $(foreach d,$(PULSE_DIRS),--include $(d)) \
  --include ./src

# ── F* verification ───────────────────────────────────────────────

# Source modules in DEPENDENCY ORDER (leaf modules first).
#
# Data.Codec.Pulse is back in: it was rewritten in Pulse (see AGENTS.md) and
# verifies/extracts to C11/OCaml/F# (Custard).  The three test modules (Roundtrip pure +
# Integration anchors + Pulse buffer roundtrips) are wired into TST_MODS below.
SRC_MODS := Data.Codec.Types Data.Codec Data.Codec.Pulse

# Pulse-only modules skip re-verification (they ship pre-verified in the F*
# install); Data.Codec.Pulse opens Pulse.Lib.* which would otherwise time out
# re-verifying the whole Pulse stdlib on every `make check`.
ALREADY_CACHED := Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore

.PHONY: check clean

# F* names its cache files `<source>.checked` (e.g. src/Data.Codec.fst ->
# Data.Codec.fst.checked) — the module's DOTS ARE PRESERVED in the .checked
# filename (only the .krml extraction name turns dots into underscores).  So
# the `check` prerequisite MUST use the raw module name, not `subst .,_`.
# (`subst .,_` here would look for Data_Codec.fst.checked, which F* never
# writes, leaving `make check` permanently out-of-date.)
# Test modules: the two coverage/roundtrip modules plus the Pulse buffer
# roundtrip tests (the 10 Stack-based tests, ported to Pulse — see AGENTS.md).
TST_MODS := Data.Codec.Test.Roundtrip Data.Codec.Test.Integration Data.Codec.Test.Pulse

check: $(addprefix $(OUT)/checked/,$(addsuffix .fst.checked,$(SRC_MODS))) \
       $(addprefix $(OUT)/checked/,$(addsuffix .fst.checked,$(TST_MODS)))

$(OUT)/checked/%.fst.checked: src/%.fst
	@mkdir -p $(OUT)/checked
	@test -n "$(FSTAR_CHECKED)" || { \
	  echo "ERROR: FSTAR_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`" >&2; \
	  exit 1; }
	# Seed the pre-verified stdlib `.checked` cache (FSTAR_CHECKED, exported by
	# the devShell) so fstar can write our module's .checked file; without the
	# dependency .checked files, fstar emits Warning 247 and never writes the
	# stamp, leaving `make check` permanently out-of-date.
	@cp $(FSTAR_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@echo "=== $* ==="
	$(FSTAR) $(FSTAR_FLAGS) \
	  --z3rlimit 120 \
	  --already_cached $(ALREADY_CACHED) \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/checked $<

$(OUT)/checked/%.fst.checked: test/%.fst
	@mkdir -p $(OUT)/checked
	@test -n "$(FSTAR_CHECKED)" || { \
	  echo "ERROR: FSTAR_CHECKED is not set; run \`nix develop\` first" >&2; \
	  exit 1; }
	@cp $(FSTAR_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@echo "=== $* ==="
	$(FSTAR) $(FSTAR_FLAGS) --include ./test \
	  --z3rlimit 120 \
	  --already_cached $(ALREADY_CACHED) \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/checked $<

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	rm -rf $(OUT) cache result result-*
