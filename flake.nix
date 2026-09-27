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

        inherit (pkgs) stdenv fstar karamel fstar-checked fstar-krml;
        inherit (pkgs) ocamlPackages;

        # ── single source of truth for renaming ────────────────────────
        #
        # ── single source of truth for renaming ────────────────────────
        #
        # Edit ONE binding below to rename the whole project.  Everything
        # user-facing (flake attribute names, exe/library basename, `.so`/
        # `.rlib`/ocaml-package names, the wasm `-no-prefix`) derives from it:
        #
        #   pname "fstar-example"  ->  .#fstar-example-checked, bin/fstar-example, libfstar-example.so, ...
        #   pname "i18n"           ->  .#i18n-checked,          bin/i18n,          libi18n.so,          ...
        #
        # The F* module is intentionally a GENERIC, never-renamed name
        # (`Example` below) so a rename is ONE edit here — there is no
        # `nix flake init --name` flag.  (The module stays `Example` unless
        # you also want to rename the source module — see README step 2.)
        pname = "fstar-codec";

        # Source modules in DEPENDENCY ORDER (leaf modules first).  The
        # library has no `main`; `Data.Codec.Low` is the single C-extractable
        # (`.Low`) module, extracted by default.nix's `.Low` filter.
        ordered-src-modules = [
          "Data.Codec.Types"
          "Data.Codec"
          "Data.Codec.Low"
        ];

        # Test modules in DEPENDENCY ORDER (Integration opens Roundtrip).
        ordered-test-modules = [
          "Data.Codec.Test.Roundtrip"
          "Data.Codec.Test.Integration"
        ];

        # The package (verify + extract), in the codec/default.nix shape.
        # default.nix returns rename-agnostic { checked; krml; }; the flake
        # exposes them as packages.<pname>-checked / -krml.
        _pkg = import ./default.nix {
          inherit pkgs pname ordered-src-modules ordered-test-modules;
        };

      in
      {
        packages.default = _pkg.krml;
        packages."${pname}-checked" = _pkg.checked;
        packages."${pname}-krml" = _pkg.krml;

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