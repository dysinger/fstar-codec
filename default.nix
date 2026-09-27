# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# Minimal verified F* package (multi-module library, .Low-extract).
#
# Takes pkgs with fstar, karamel, fstar-checked in scope (from the nixpkgs
# overlay in the top-level flake), plus the project name and the ordered list
# of source modules (both threaded from the top-level flake).
#
# Returns { checked; krml; } — rename-agnostic keys.  The top-level flake
# exposes them as packages.<pname>-checked / -krml.

{ pkgs, pname ? "fstar-example", ordered-src-modules ? ["Data.Codec.Types" "Data.Codec" "Data.Codec.Low"] }:

let
  inherit (pkgs) stdenv fstar karamel fstar-checked;

  fstar-exe = "${fstar}/bin/fstar.exe";
  ulib = "${fstar}/lib/fstar/ulib";
  krmllib = "${karamel.home}/krmllib";

  fstar-flags = "--no_default_includes --include ${ulib} --include ./src --include ${krmllib} --include ${krmllib}/obj --z3rlimit 80";

  # Source modules in DEPENDENCY ORDER (leaf modules first).  Required so the
  # .checked files land in $out in the right order (Warning 247).
  checked = stdenv.mkDerivation {
    pname = "${pname}-checked";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ fstar ];
    meta = {
      license = pkgs.lib.licenses.agpl3Plus;
      maintainers = [{
        name = "Tim Dysinger";
        email = "tim@dysinger.net";
      }];
    };
    # Write straight to $out in buildPhase and no-op installPhase — these
    # derivations just stage a directory of compiler artifacts, not a
    # build/install split.
    buildPhase = ''
      mkdir -p $out
      cp ${fstar-checked}/*.checked $out/ 2>/dev/null || true

      for mod in ${builtins.concatStringsSep " " ordered-src-modules}; do
        echo "=== Verifying $mod ==="
        ${fstar-exe} ${fstar-flags} \
          --cache_checked_modules --cache_dir $out --odir $out \
          src/$mod.fst || exit 1
      done
      rm -f $out/*.krml $out/*.c $out/*.h 2>/dev/null || true
      echo "checked: $(ls $out/*.checked 2>/dev/null | wc -l) files"
    '';
    installPhase = "true";
  };

  krml = stdenv.mkDerivation {
    pname = "${pname}-krml";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ fstar ];
    meta = {
      license = pkgs.lib.licenses.agpl3Plus;
      maintainers = [{
        name = "Tim Dysinger";
        email = "tim@dysinger.net";
      }];
    };
    buildPhase = ''
      mkdir -p $out
      cp ${checked}/*.checked $out/ 2>/dev/null || true
      cp ${fstar-checked}/*.checked $out/ 2>/dev/null || true

      # Extract only the `.Low` modules (the C-extractable surface), per the
      # multi-module library convention.  The pure spec + type modules are
      # verified in `checked` but not extracted.
      for mod in ${builtins.concatStringsSep " " ordered-src-modules}; do
        case "$mod" in
          *.Low)
            echo "=== Extracting $mod ==="
            ${fstar-exe} ${fstar-flags} \
              --cache_checked_modules --cache_dir $out \
              --odir $out --codegen krml \
              --extract_module $mod \
              src/$mod.fst || exit 1
            ;;
          *) ;;
        esac
      done
      rm -f $out/*.checked $out/*.c $out/*.h $out/*.exe 2>/dev/null || true
      echo "krml: $(ls $out/*.krml 2>/dev/null | wc -l) files"
    '';
    installPhase = "true";
  };
in
{
  inherit checked krml;
}
