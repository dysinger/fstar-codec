# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# fstar-codec — Data.Codec verified bidirectional codec library.
#
# Takes the F* / KaRaMeL toolchain as concrete derivations (no `pkgs` blob, no
# overlay assumption, no module-name/order arguments).  Module names and their
# dependency order live in the Makefile (the no-nix build); `checked` and
# `krml` delegate to `make`, exporting the toolchain paths the Makefile
# already reads.
#
# Backend coverage mirrors the template minus F# and exe (a library has no
# `main` entry): native (C shared object), rust (`.rlib`), ocaml (findlib
# package of the pure spec modules), and wasm (module of the `.Low` surface).
# The C/rust/wasm backends consume `Data_Codec_Low.krml` (the `.Low` module);
# ocaml consumes the pure modules `Data.Codec.Types` + `Data.Codec`.
#
# Returns { checked; krml; native; rust; ocaml; wasm; }.

{ fstar, fstar-checked, fstar-krml, karamel, lib, ocamlPackages, rustc, stdenv }:

let
  inherit (stdenv) mkDerivation;

  pname = "fstar-codec";

  # The single C-extractable (`.Low`) module, and the pure (OCaml-extractable)
  # modules.  Discovered from the source tree, not passed in as arguments.
  low-module = "Data.Codec.Low";
  pure-modules = [ "Data.Codec.Types" "Data.Codec" ];

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
  # ── KaRaMeL C / Rust / wasm backends ───────────────────────────────
  #
  # These consume the extracted `Data_Codec_Low.krml` (the `.Low` module).
  # The `.krml` extraction name turns dots into underscores.

  low-krml-name = builtins.replaceStrings [ "." ] [ "_" ] low-module; # Data_Codec_Low

  # The KaRaMeL runtime `.krml` files `Data.Codec.Low` actually reaches.  The
  # extracted `Data_Codec_Low.krml` references only these modules (its spec
  # code — the `codec a` combinator layer and the two pure spec predicates —
  # is `Ghost`/`noextract` and erased from the `.krml`).  Do NOT glob all of
  # `${fstar-krml}/krml/*.krml` (thousands of files incl. `FStar_List_Tot_Base`);
  # that bundle forces the `FStar.List` reachability that the rust/wasm backends
  # cannot translate.
  krml-runtime = [
    "FStar_UInt" "FStar_Int" "FStar_UInt8" "FStar_UInt16" "FStar_UInt32"
    "FStar_Seq_Base" "FStar_Int_Cast" "FStar_Pervasives"
    "LowStar_Buffer"
    "FStar_HyperStack" "FStar_HyperStack_ST"
    "FStar_Monotonic_Heap" "FStar_Monotonic_HyperHeap" "FStar_Monotonic_HyperStack"
  ];
  krml-runtime-paths = map (m: "${fstar-krml}/krml/" + m + ".krml") krml-runtime;
  warn-errors = "-warn-error -2 -warn-error -9-16 -warn-error -11 -warn-error -26..28";


  native = mkDerivation {
    name = "${pname}-native";
    src = ./. ;
    nativeBuildInputs = [ fstar karamel stdenv.cc ];
    inherit meta;
    buildPhase = ''
      mkdir -p native-out
      export KRML_HOME="${karamel.home}"
      ${krml-exe} \
        -skip-compilation \
        -ccflavor clang \
        -tmpdir native-out \
        ${warn-errors} \
        -add-include '"krml/internal/compat.h"' \
        -no-prefix 'Data.Codec.*' \
        ${builtins.concatStringsSep " " krml-runtime-paths} \
        ${krml}/${low-krml-name}.krml
      if [ "$(uname)" = Darwin ]; then so_ext=dylib; else so_ext=so; fi
      KRM_INC="-I${karamel.home}/include -I${karamel.home}/krmllib/c -I${karamel.home}/krmllib/dist/minimal"
      for cfile in native-out/*.c; do
        cc -O3 -fno-strict-aliasing -std=c11 -Inative-out $KRM_INC \
          -c "$cfile" -o "''${cfile%.c}.o" || exit 1
      done
      cc -shared -fPIC \
        -o native-out/lib${pname}."$so_ext" \
        native-out/*.o \
        ${karamel.home}/krmllib/dist/generic/libkrmllib.a
    '';
    installPhase = ''
      mkdir -p $out/lib $out/include
      cp native-out/*.so native-out/*.dylib $out/lib/ 2>/dev/null || true
      cp native-out/${low-krml-name}.h $out/include/ 2>/dev/null || true
      if [ ! -f "$out/lib/lib${pname}.so" ] && [ ! -f "$out/lib/lib${pname}.dylib" ]; then
        echo "ERROR: no shared object produced" >&2
        exit 1
      fi
    '';
  };

  wasm = mkDerivation {
    name = "${pname}-wasm";
    src = ./. ;
    nativeBuildInputs = [ fstar karamel ];
    inherit meta;
    buildPhase = ''
      mkdir -p wasm-out
      export KRML_HOME="${karamel.home}"
      ${krml-exe} \
        -tmpdir wasm-out \
        -backend wasm \
        ${warn-errors} \
        -add-include '"krml/internal/compat.h"' \
        -no-prefix 'Data.Codec.*' \
        ${builtins.concatStringsSep " " krml-runtime-paths} \
        ${fstar-krml}/krml/WasmSupport.krml \
        ${krml}/${low-krml-name}.krml
    '';
    installPhase = ''
      mkdir -p $out
      cp wasm-out/* $out/ 2>/dev/null || true
      if [ ! -f "$out/${low-krml-name}.wasm" ]; then
        echo "ERROR: expected $out/${low-krml-name}.wasm, but found:" >&2
        ls -1 "$out" | grep '\.wasm$' >&2 || true
        exit 1
      fi
      echo "wasm: $(ls $out/*.wasm 2>/dev/null | wc -l) .wasm file(s)"
    '';
  };

  rust-src = mkDerivation {
    name = "${pname}-rust-src";
    src = ./. ;
    nativeBuildInputs = [ fstar karamel ];
    buildPhase = ''
      mkdir -p $out
      export KRML_HOME="${karamel.home}"
      ${krml-exe} \
        -minimal \
        -bundle ${low-module}=\* \
        -tmpdir $out \
        -backend rust \
        ${warn-errors} \
        -add-include '"krml/internal/compat.h"' \
        ${builtins.concatStringsSep " " krml-runtime-paths} \
        ${krml}/${low-krml-name}.krml
    '';
    installPhase = "true";
  };

  rust = mkDerivation {
    name = "${pname}-rust";
    src = rust-src;
    nativeBuildInputs = [ rustc ];
    inherit meta;
    buildPhase = ''
      CRATE="$(printf '%s' '${pname}' | tr '-' '_')"
      # `-bundle Data.Codec.Low=*` emits `data/codec_low.rs` (module path,
      # lowercased and underscored), not `Data_Codec_Low.rs`.
      rustc --crate-type lib data/codec_low.rs --crate-name "$CRATE" -o lib${pname}.rlib
    '';
    installPhase = ''
      mkdir -p $out/lib
      cp lib${pname}.rlib $out/lib/
    '';
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
    nativeBuildInputs = [ fstar ];
    buildPhase = ''
      mkdir -p $out
      export ULIB="${fstar}/lib/fstar/ulib"
      ${fstar-exe} \
        --no_default_includes --include $ULIB --include ./src \
        --codegen OCaml --odir $out \
        ${builtins.concatStringsSep " " (map (m: "src/" + m + ".fst") pure-modules)} || exit 1
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
  inherit checked krml native rust ocaml wasm;
}
