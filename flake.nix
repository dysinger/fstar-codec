# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "Minimal verified F* project template (fstar-example)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c31cf09";
    flake-utils.url = "github:numtide/flake-utils";
    fstar = {
      url = "github:dysinger/fstar/v2025.10.06+lsp";
      flake = false;
    };
    karamel = {
      url = "github:dysinger/karamel/coextract";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (_final: prev:
              if prev.stdenv.isDarwin && prev.stdenv.isAarch64 then {
                # Skip OCaml's own testsuite on aarch64-darwin.
                ocaml-ng = prev.ocaml-ng // {
                  ocamlPackages_5_3 = prev.ocaml-ng.ocamlPackages_5_3.overrideScope (_: _: {
                    ocaml = prev.ocaml-ng.ocamlPackages_5_3.ocaml.overrideAttrs (_: {
                      checkPhase = "true";
                    });
                  });
                };
              } else { })
            (_final: prev:
              let
                z3 = prev.callPackage (inputs.fstar + "/.nix/z3.nix") { };
                ocamlPackages = prev.ocaml-ng.ocamlPackages_5_3;
                fstar = (ocamlPackages.callPackage (inputs.fstar + "/.nix/fstar.nix") {
                  version = "unknown";
                  inherit z3;
                }).overrideAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.git ];
                });
                gtime = prev.runCommand "gtime" { } ''
                  mkdir -p $out/bin
                  ln -s ${prev.time}/bin/time $out/bin/gtime
                '';
                # fstar-checked: ulib .checked files (pre-verified by fstar compiler).
                fstar-checked = prev.runCommand "fstar-checked"
                  { nativeBuildInputs = [ fstar ]; }
                  ''
                    mkdir -p $out
                    cp ${fstar}/lib/fstar/ulib.checked/*.checked $out/ 2>/dev/null || true
                    echo "checked: $(ls $out/*.checked 2>/dev/null | wc -l) files"
                  '';
                karamel = (prev.callPackage (inputs.karamel + "/.nix/karamel.nix") {
                  inherit fstar ocamlPackages z3;
                  version = "unknown";
                }).overrideAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ gtime ];
                });
                # fstar-krml: krmllib .krml + ulib .fsti/.fst (flat, for downstream
                # typecheckers and the Makefile-driven C link).
                fstar-krml = prev.runCommand "fstar-krml"
                  { nativeBuildInputs = [ fstar karamel ]; }
                  ''
                    mkdir -p $out/krml $out/extract
                    cp ${karamel.home}/krmllib/.extract/*.krml $out/krml/ 2>/dev/null || true
                    ULIB_DIR=${fstar}/lib/fstar/ulib
                    find $ULIB_DIR -name '*.fsti' -exec cp {} $out/extract/ \; 2>/dev/null || true
                    find $ULIB_DIR -name '*.fst' -exec cp {} $out/extract/ \; 2>/dev/null || true
                    echo "krml: $(ls $out/krml/*.krml 2>/dev/null | wc -l) files"
                    echo "extract: $(ls $out/extract/ 2>/dev/null | wc -l) files"
                  '';
              in
              {
                inherit fstar karamel fstar-checked fstar-krml;
                # The OCaml 5.3 package set F* itself is built against
                # (carries batteries/pprint/stdint/yojson/zarith, the deps
                # fstar.lib's OCaml runtime requires for ocamlfind linking).
                ocamlPackages = prev.ocaml-ng.ocamlPackages_5_3;
              })
          ];
        };

        inherit (pkgs) stdenv fstar karamel fstar-checked fstar-krml lib rustc;
        inherit (pkgs) ocamlPackages;

        # The package.  All derivation logic (verify + extract + backends)
        # lives in default.nix, which takes the toolchain by named argument
        # and delegates module order to the Makefile.  This flake only
        # re-exposes the targets (everything but F#; no exe, as the library
        # has no `main`).
        _pkg = import ./default.nix {
          inherit fstar fstar-checked fstar-krml karamel lib ocamlPackages rustc stdenv;
        };

      in
      {
        packages.default = _pkg.krml;
        packages.fstar-codec-checked = _pkg.checked;
        packages.fstar-codec-krml = _pkg.krml;
        packages.fstar-codec-native = _pkg.native;
        packages.fstar-codec-rust = _pkg.rust;
        packages.fstar-codec-ocaml = _pkg.ocaml;
        packages.fstar-codec-wasm = _pkg.wasm;

        devShells.default = pkgs.mkShell {
            dontDetectOcamlConflicts = true;
            shellHook = ''
              export FSTAR_KRML="${fstar-krml}"
              export FSTAR_CHECKED="${fstar-checked}"
              export KRML_HOME="${karamel.home}"
              export KRM_LIB="${karamel.home}/krmllib"
              export KRM_INC="-I${karamel.home}/include -I${karamel.home}/krmllib/c -I${karamel.home}/krmllib/dist/minimal"
            '';
            buildInputs = with pkgs; [
              fstar
              karamel
              ocaml
              ocamlPackages.ocaml-lsp
              python3
            ];
          };
      }
    );
}