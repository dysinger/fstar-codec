# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# F* dev-loop build (verify + KaRaMeL extract + native link).
#
# Usage: nix develop, then `make check` / `make krml` / `make exe`.
#
# The FSTAR_KRML / KRML_HOME / KRM_LIB / KRM_INC env vars are exported by the
# flake devShell (see flake.nix shellHook).  Override them here if needed.

# ── Tools ──────────────────────────────────────────────────────────

CC ?= cc
CFLAGS = -O3 -fno-strict-aliasing -ffunction-sections -fdata-sections
ifeq ($(shell uname),Darwin)
  LDFLAGS = -Wl,-dead_strip
else
  LDFLAGS = -Wl,--gc-sections
endif

OUT := out

FSTAR ?= fstar.exe
KRML  ?= krml

# These are supplied by the flake devShell's shellHook, which exports
# FSTAR_KRML / FSTAR_CHECKED / KRML_HOME / KRM_LIB / KRM_INC.  Make imports
# them from the environment as ordinary variables of the same name; passing
# e.g. `make exe KRM_LIB=/elsewhere` on the command line simply overrides the
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

KRM_LIB_A ?= $(KRM_LIB)/dist/generic/libkrmllib.a

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
# Data.Codec.Types (Warning 247).  Keep in sync with default.nix's
# `ordered-src-modules`.
SRC_MODS := Data.Codec.Types Data.Codec Data.Codec.Low

# Modules to extract to C via KaRaMeL.  A library extracts only its `.Low`
# (C-extractable) modules.
_LO_MODS := $(filter %.Low,$(SRC_MODS))
KRML_MODS := $(if $(_LO_MODS),$(_LO_MODS),$(SRC_MODS))

# The source module name is auto-discovered from `module Foo` in src/*.fst,
# so a module rename (file + `module` header) needs NO Makefile edit.  MODULE
# is the (capitalized) module name; PNAME is the native executable basename.
# PNAME is OVERRIDEABLE (the flake's <pname>-exe derivation passes it as the
# project name); standalone `make exe` falls back to the lowercased module
# name.
MODULE := $(firstword $(SRC_MODS))
PNAME  ?= $(shell printf '%s' '$(MODULE)' | tr 'A-Z' 'a-z')

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
