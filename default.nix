# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# fstar-codec — Data.Codec verified bidirectional codec library.
#
# Takes the F* / KaRaMeL toolchain as concrete derivations (no `pkgs` blob, no
# overlay assumption, no module-name/order arguments).  Module names and their
# dependency order live in the Makefile (the no-nix build); `checked` and
# `krml` delegate to `make`, exporting the toolchain paths the Makefile
# already reads.  A library has no `main`, so there are no exe/native/rust/
# ocaml/wasm targets.
#
# Returns { fstar-codec-checked; fstar-codec-krml; }.

{ fstar, fstar-checked, fstar-krml, karamel, lib, stdenv }:

let
  inherit (stdenv) mkDerivation;

  pname = "fstar-codec";

  fstar-exe = "${fstar}/bin/fstar.exe";
  krml-exe = "${karamel}/bin/krml";

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
    export KRML="${krml-exe}"
    export FSTAR_KRML="${fstar-krml}"
    export FSTAR_CHECKED="${fstar-checked}"
    export KRML_HOME="${karamel.home}"
    export KRM_LIB="${karamel.home}/krmllib"
    export KRM_INC="-I${karamel.home}/include -I${karamel.home}/krmllib/c -I${karamel.home}/krmllib/dist/minimal"
  '';

  checked = mkDerivation {
    pname = "${pname}-checked";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ fstar karamel fstar-krml fstar-checked ];
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

  krml = mkDerivation {
    pname = "${pname}-krml";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ fstar karamel fstar-krml fstar-checked ];
    inherit meta;
    buildPhase = ''
      ${make-env}
      make krml OUT="$out"
      # Flatten $(OUT)/krml/*.krml to $out/*.krml; drop the intermediate
      # $(OUT)/checked/.
      if [ -d "$out/krml" ]; then mv "$out"/krml/*.krml "$out"/ 2>/dev/null || true; rmdir "$out/krml"; fi
      rm -rf "$out/checked"
    '';
    installPhase = "true";
  };
in
{
  inherit checked krml;
}
