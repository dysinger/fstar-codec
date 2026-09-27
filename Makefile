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

FSTAR_FLAGS = --no_default_includes \
  --include $(ULIB) \
  --include ./src

# ── F* verification ───────────────────────────────────────────────

# Source modules in DEPENDENCY ORDER (leaf modules first).
#
# NOTE: Data.Codec.Low (the KaRaMeL Low* leaf) is excluded: F* v2026.09.20
# removed the entire Low*/KaRaMeL stdlib (FStar.HyperStack, FStar.HyperStack.ST,
# LowStar.Buffer), so it cannot typecheck anymore.  Porting it to Pulse is the
# next change.  The two test modules likewise depend on Data.Codec.Low and are
# excluded until then.
SRC_MODS := Data.Codec.Types Data.Codec

.PHONY: check clean

# F* names its cache files `<source>.checked` (e.g. src/Data.Codec.fst ->
# Data.Codec.fst.checked) — the module's DOTS ARE PRESERVED in the .checked
# filename (only the .krml extraction name turns dots into underscores).  So
# the `check` prerequisite MUST use the raw module name, not `subst .,_`.
# (`subst .,_` here would look for Data_Codec.fst.checked, which F* never
# writes, leaving `make check` permanently out-of-date.)
# Tests are also excluded for now (they `open Data.Codec.Low`).
TST_MODS :=

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
	  --z3rlimit 80 \
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
	  --z3rlimit 80 \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/checked $<

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	rm -rf $(OUT)
