# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# fstar-codec — Data.Codec verified bidirectional codec library.
#
# Takes the F* toolchain as concrete derivations (no `pkgs` blob, no overlay
# assumption, no module-name/order arguments).  Module names and their
# dependency order live in the Makefile (the no-nix build); `checked` delegates
# to `make check`, exporting the toolchain paths the Makefile already reads.
#
# Backends:
#   - `checked` — F* verification of src/ + test/ (the 0-admit gate).
#   - `ocaml`   — findlib package of the pure spec modules
#                 (`Data.Codec.Types` + `Data.Codec`).
#   - `native`  — C11 shared/static lib of the Pulse leaf (`Data.Codec.Pulse`)
#                 via Custard (`--custard_backend C`), no karamel.
#
# Returns { checked; ocaml; native; }.

{ fstar, fstar-checked, lib, ocamlPackages, stdenv }:

let
  inherit (stdenv) mkDerivation;

  pname = "fstar-codec";

  pure-modules = [ "Data.Codec.Types" "Data.Codec" ];

  fstar-exe = "${fstar}/bin/fstar.exe";

  meta = {
    license = lib.licenses.agpl3Plus;
    maintainers = [{
      name = "Tim Dysinger";
      email = "tim@dysinger.net";
    }];
  };

  # The toolchain environment the Makefile reads (see its guards).
  make-env = ''
    export FSTAR="${fstar-exe}"
    export FSTAR_CHECKED="${fstar-checked}"
  '';

  checked = mkDerivation {
    pname = "${pname}-checked";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ fstar fstar-checked ];
    inherit meta;
    buildPhase = ''
      ${make-env}
      make check OUT="$out"
      # Flatten $(OUT)/checked/*.checked to $out/*.checked (the old default.nix
      # shipped a flat .checked artifact).
      if [ -d "$out/checked" ]; then mv "$out"/checked/*.checked "$out"/ 2>/dev/null || true; rmdir "$out/checked"; fi
    '';
    installPhase = "true";
  };

  # ── OCaml source backend ────────────────────────────────────────────
  #
  # `fstar.exe --codegen OCaml` extracts the pure spec modules (the `codec`
  # type + combinators), not the `Pulse` implementation.

  # dune library name + module names: OCaml module names are the F* module
  # names with dots turned into underscores (fstar.exe --codegen OCaml emits
  # Data_Codec_Types.ml / Data_Codec.ml).  The findlib public_name keeps the
  # hyphen.
  ocaml-lib-name = builtins.replaceStrings [ "-" ] [ "_" ] pname;
  ocaml-modules = map (m: builtins.replaceStrings [ "." ] [ "_" ] m) pure-modules;

  ocaml-src = mkDerivation {
    name = "${pname}-ocaml-src";
    src = ./. ;
    nativeBuildInputs = [ fstar fstar-checked ];
    buildPhase = ''
      mkdir -p $out
      export ULIB="${fstar}/lib/fstar/ulib"
      # Seed the pre-verified stdlib cache so cross-module inlining can find
      # our own modules' `.checked` files (Error 317 otherwise).
      mkdir -p cache
      cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
      # Verify in dependency order, then extract one module per invocation
      # (F* v2026.09.20 requires one file per --codegen OCaml run).
      for m in ${builtins.concatStringsSep " " pure-modules}; do
        ${fstar-exe} \
          --no_default_includes --include $ULIB --include ./src \
          --cache_checked_modules --cache_dir cache --odir cache \
          src/$m.fst || exit 1
        ${fstar-exe} \
          --no_default_includes --include $ULIB --include ./src --include cache \
          --cache_checked_modules --cache_dir cache \
          --codegen OCaml --odir $out \
          src/$m.fst || exit 1
      done
      cat > $out/dune-project <<DUNE_PROJECT
(lang dune 3.11)
(name ${pname}-ocaml)
(package (name ${pname}-ocaml))
DUNE_PROJECT
      cat > $out/dune <<DUNE
(library
 (name ${ocaml-lib-name})
 (public_name ${pname}-ocaml)
 (modules ${builtins.concatStringsSep " " ocaml-modules})
 (libraries fstar.lib))
DUNE
    '';
    installPhase = "true";
  };

  ocaml = ocamlPackages.buildDunePackage {
    pname = "${pname}-ocaml";
    version = "0.1.0";
    src = ocaml-src;
    inherit meta;
    propagatedBuildInputs = [ fstar ];
    buildInputs = with ocamlPackages; [
      batteries pprint stdint yojson zarith
      ppx_deriving ppx_deriving_yojson
    ];
    OCAMLPATH = "${fstar}/lib";
  };

  # ── native (C) backend via Custard ─────────────────────────────────
  #
  # `--codegen Custard --custard_backend C` extracts the Pulse leaf
  # (`Data.Codec.Pulse`) to C11 with no karamel runtime.  The whole module is a
  # library (no `main`), rooted with `--custard_entry_module`.  The C backend
  # requires `--custard_monomorphize_types true`.

  flib = "${fstar}/lib/fstar";
  pulse-incs = [
    "${flib}/pulse/common"
    "${flib}/pulse/common.checked"
    "${flib}/pulse/pulse/lib"
    "${flib}/pulse/pulse.checked"
  ];

  native = mkDerivation {
    pname = "${pname}-native";
    version = "0.1.0";
    src = ./. ;
    nativeBuildInputs = [ fstar fstar-checked ];
    inherit meta;
    buildPhase = ''
      mkdir -p $out cache
      ULIB="${flib}/ulib"
      PULSE_INCS=""
      for d in ${lib.concatStringsSep " " pulse-incs}; do
        PULSE_INCS="$PULSE_INCS --include $d"
      done
      # Seed the cache with pre-verified stdlib `.checked` files so
      # `--already_cached Prims,FStar,...` can resolve (Error 317 otherwise).
      cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
      # Verify in dependency order into a cache so cross-module inlining
      # (Error 317) can find our own modules' `.checked` files.
      for m in Data.Codec.Types Data.Codec Data.Codec.Pulse; do
        ${fstar-exe} \
          --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src \
          --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
          --z3rlimit 120 \
          --cache_checked_modules --cache_dir cache --odir cache \
          src/$m.fst || exit 1
      done
      # Extract the whole `Data.Codec.Pulse` module to C (library mode).
      ${fstar-exe} \
        --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src --include cache \
        --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
        --cache_checked_modules --cache_dir cache \
        --codegen Custard --custard_backend C --custard_monomorphize_types true \
        --custard_entry_module Data.Codec.Pulse --odir $out \
        src/Data.Codec.Pulse.fst || exit 1
      # Compile the emitted C11 to a shared object + static lib (no karamel).
      cc -c -Wall -Wextra -Werror -std=c11 -O2 -fPIC -I $out $out/Custard.c -o $out/Custard.o
      if [ "$(uname -s)" = Darwin ]; then
        cc -dynamiclib $out/Custard.o -o $out/lib${pname}.dylib
      else
        cc -shared $out/Custard.o -o $out/lib${pname}.so
      fi
      ar rcs $out/lib${pname}.a $out/Custard.o
      # Publish a stable header name alongside Custard.h.
      cp $out/Custard.h $out/fstar_codec.h
    '';
    installPhase = "true";
  };
in
{
  inherit checked ocaml native;
}
