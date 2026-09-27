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
#
# The `.Low` C leaf (`Data.Codec.Low`) is not in a backend yet: the KaRaMeL
# Low* target was removed with the karamel toolchain, and the Custard
# direct-C backend extracts Pulse, not the `Stack`/`LowStar.Buffer` style the
# leaf is currently written in.  Porting the leaf to Pulse is tracked as the
# next change.
#
# Returns { checked; ocaml; }.

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
  # type + combinators), not the `.Low` Stack implementation.

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
in
{
  inherit checked ocaml;
}
