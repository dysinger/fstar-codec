# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# F* dev-loop build (verify + KaRaMeL extract).
#
# Usage: nix develop, then `make check` / `make krml`.
#
# The FSTAR_KRML / KRML_HOME / KRM_LIB / KRM_INC env vars are exported by the
# flake devShell (see flake.nix shellHook).  Override them here if needed.

# ── Tools ──────────────────────────────────────────────────────────

# Build output directory.  Defaults to `./out` for the dev loop; nix
# derivations (default.nix) override it to `$out` so the Makefile writes
# straight into the nix store output path.
OUT ?= out

FSTAR ?= fstar.exe

# These are supplied by the flake devShell's shellHook, which exports
# FSTAR_KRML / FSTAR_CHECKED / KRML_HOME / KRM_LIB / KRM_INC.  Make imports
# them from the environment as ordinary variables of the same name; passing
# e.g. `make krml KRM_LIB=/elsewhere` on the command line simply overrides the
# environment import.  No `?=` here (a same-name `?= $(VAR)` is a recursive
# self-reference when the env var is missing).  The guards below make a
# missing value fail loudly instead of silently mis-resolving.

ifeq ($(FSTAR_KRML),)
$(error FSTAR_KRML is not set; run `nix develop` (or export it yourself) before `make`)
endif
ifeq ($(KRML_HOME),)
$(error KRML_HOME is not set; run `nix develop` (or export it yourself) before `make`)
endif
ifeq ($(KRM_LIB),)
$(error KRM_LIB is not set; run `nix develop` (or export it yourself) before `make`)
endif

ULIB := $(shell $(FSTAR) --locate_lib 2>/dev/null || echo /none)/ulib
KRM_LIB_DIR := $(or $(KRML_HOME)/krmllib,$(KRM_LIB))

FSTAR_FLAGS = --no_default_includes \
  --include $(ULIB) \
  --include ./src \
  --include $(KRM_LIB_DIR) \
  --include $(KRM_LIB_DIR)/obj

# ── F* verification ───────────────────────────────────────────────

# Source modules in DEPENDENCY ORDER (leaf modules first), overriding the
# template's auto-discovered `sort` which would alphabetize Data.Codec before
# Data.Codec.Types and trigger F* Warning 247 (a dependent module verified
# before its leaf never writes its .checked).  Note: Data.Codec.Low depends on
# Data.Codec.Types only (it does not open Data.Codec), so this order is a
# valid linearization (Types -> Codec, Types -> Low), not a minimal chain.
SRC_MODS := Data.Codec.Types Data.Codec Data.Codec.Low

# Modules to extract to C via KaRaMeL.  A library extracts only its `.Low`
# (C-extractable) modules.  Fail loudly if the filter ever comes up empty
# (e.g. due to a copy-paste of the `grep '\.Low\.'` defect) rather than
# silently producing an empty krml artifact.
_LO_MODS := $(filter %.Low,$(SRC_MODS))
KRML_MODS := $(if $(_LO_MODS),$(_LO_MODS),$(SRC_MODS))
ifeq ($(KRML_MODS),)
$(error KRML_MODS is empty; expected at least one .Low module to extract)
endif

.PHONY: check krml clean

# F* names its cache files `<source>.checked` (e.g. src/Data.Codec.fst ->
# Data.Codec.fst.checked) — the module's DOTS ARE PRESERVED in the .checked
# filename (only the .krml extraction name turns dots into underscores).  So
# the `check` prerequisite MUST use the raw module name, not `subst .,_`.
# (`subst .,_` here would look for Data_Codec.fst.checked, which F* never
# writes, leaving `make check` permanently out-of-date.)
TST_MODS := Data.Codec.Test.Roundtrip Data.Codec.Test.Integration

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

# ── KaRaMeL extraction ─────────────────────────────────────────────

krml: check $(addprefix $(OUT)/krml/,$(addsuffix .krml,$(subst .,_,$(KRML_MODS))))

define KRML_RULE
$(OUT)/krml/$(subst .,_,$(1)).krml: src/$(1).fst
	@mkdir -p $(OUT)/krml
	$(FSTAR) $(FSTAR_FLAGS) \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/krml --codegen krml \
	  --extract_module $(1) $$<
endef
$(foreach mod,$(KRML_MODS),$(eval $(call KRML_RULE,$(mod))))

clean:
	rm -rf $(OUT)
