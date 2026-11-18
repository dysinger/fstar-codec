# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# codec — Data.Codec verified bidirectional codec library.
#
# Takes the F* toolchain as concrete derivations (no `pkgs` blob, no overlay
# assumption, no module-name/order arguments).  Module names and their
# dependency order live in the Makefile (the no-nix build); `checked` delegates
# to `make check`, exporting the toolchain paths the Makefile already reads.
#
# Artifacts (named by deliverable, not by backend):
#   - `checked` — F* verification of src/ + test/ (the 0-admit gate).
#   - `bench`   — runs the C benchmark (extracted C vs hand-written baseline)
#                 and ships its output (REQ-ISO-C-PERF).
#   - `ocaml`   — findlib package shipping ALL OCaml-extractable modules:
#                 the pure spec (`Data.Codec.Types` + `Data.Codec` via
#                 `--codegen OCaml`) AND the Pulse leaf (`Data.Codec.Pulse`,
#                 `--custard_backend OCaml`) as one dune library.
#   - `native`  — C11 shared/static lib of the Pulse leaf (`Data.Codec.Pulse`,
#                 `--custard_backend C`).
#
# Returns { checked; ocaml; native; fsharp; bench; }.

{
  fstar,
  fstar-checked,
  lib,
  ocamlPackages,
  stdenv,
  dotnet,
}:

let
  inherit (stdenv) mkDerivation;

  # Package name.  The package is "codec" (git repo "fstar-codec"), but the internal
  # derivation/artifact names drop the "fstar-" prefix (→ codec-checked,
  # codec-ocaml, codec-native, codec-fsharp, libcodec.*, codec.h).
  pname = "codec";

  pure-modules = [
    "Data.Codec.Types"
    "Data.Codec.Text"
    "Data.Codec"
  ];

  fstar-exe = "${fstar}/bin/fstar.exe";

  meta = {
    license = lib.licenses.agpl3Plus;
    maintainers = [
      {
        name = "Tim Dysinger";
        email = "tim@dysinger.net";
      }
    ];
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
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
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
    name = "ocaml-src";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    buildPhase = ''
            mkdir -p $out
            export ULIB="${fstar}/lib/fstar/ulib"
            # Seed the pre-verified stdlib cache so cross-module inlining can find
            # our own modules' `.checked` files (Error 317 otherwise).
            mkdir -p cache
            cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
            # 1) Extract the pure spec (Data.Codec.Types + Data.Codec) via
            #    `--codegen OCaml` (one file per invocation, in dependency order).
            #    On this toolchain every `--codegen` goes through Custard, so an
            #    entry point is REQUIRED (Error 155 otherwise) — the whole module
            #    is the natural root for a pure-spec module.
            #    The OCaml backend names its output `Custard.ml` whatever the
            #    module, so `-o` gives each module its own file (otherwise each
            #    invocation overwrites the last and only one `.ml` survives).
            #    The last invocation also emits `Custard.ml` (the module-to-
            #    filename map is what `dune` lists); it is `-o Custard.ml` too.
            for m in ${builtins.concatStringsSep " " pure-modules}; do
              ${fstar-exe} \
                --no_default_includes --include $ULIB --include ./src \
                --cache_checked_modules --cache_dir cache --odir cache \
                src/$m.fst || exit 1
              ${fstar-exe} \
                --no_default_includes --include $ULIB --include ./src --include cache \
                --cache_checked_modules --cache_dir cache \
                --codegen OCaml --custard_entry_module $m \
                -o $out/$(echo $m | tr . _).ml \
                src/$m.fst || exit 1
            done
            # 2) Extract the Pulse leaf (Data.Codec.Pulse), OCaml backend.
            PULSE_INCS=""
            for d in ${lib.concatStringsSep " " pulse-incs}; do
              PULSE_INCS="$PULSE_INCS --include $d"
            done
            for m in Data.Codec.Pulse; do
              ${fstar-exe} \
                --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src \
                --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
                --z3rlimit 120 \
                --cache_checked_modules --cache_dir cache --odir cache \
                src/$m.fst || exit 1
            done
            ${fstar-exe} \
              --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src --include cache \
              --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
              --cache_checked_modules --cache_dir cache \
              --codegen OCaml --custard_monomorphize_types true \
              --custard_entry Data.Codec.Pulse.encode_bytes \
              --custard_entry Data.Codec.Pulse.decode_bytes \
              --odir $out \
              src/Data.Codec.Pulse.fst || exit 1
            # One dune library: pure spec + Pulse leaf together.
            cat > $out/dune-project <<DUNE_PROJECT
      (lang dune 3.11)
      (name ${pname}-ocaml)
      (package (name ${pname}-ocaml))
      DUNE_PROJECT
            cat > $out/dune <<DUNE
      (library
       (name ${ocaml-lib-name})
       (public_name ${pname}-ocaml)
       (modules ${builtins.concatStringsSep " " ocaml-modules} Custard)
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
      batteries
      pprint
      stdint
      yojson
      zarith
      ppx_deriving
      ppx_deriving_yojson
    ];
    OCAMLPATH = "${fstar}/lib";
  };

  # ── native (C) backend ─────────────────────────────────────────────
  #
  # `--codegen C` (Custard's C backend) extracts the Pulse leaf
  # (`Data.Codec.Pulse`) to C11.  The flag is `--codegen C`, NOT
  # `--codegen Custard`: the enum is OCaml|FSharp|KrmlC|KrmlRust|C|Cherry|Plugin
  # and `--codegen Custard` is rejected outright.  `--custard_backend` is not
  # an option at all on this toolchain.  The whole module is a library (no
  # `main`), so it is rooted with `--custard_entry_module`, which also emits
  # the public definitions under their bare names (as krml's `-no-prefix`).
  #
  # Measured on this host (2026-11-18): verify 4 modules from cold + extract +
  # compile `-Werror` = 63 s total.  The "#native hangs at 0% CPU" note was
  # the rejected flag plus, in a different attempt, a cold Types verify; the
  # cold Types verify alone is 24 s and green.

  flib = "${fstar}/lib/fstar";
  pulse-incs = [
    "${flib}/pulse/common"
    "${flib}/pulse/common.checked"
    "${flib}/pulse/pulse/lib"
    "${flib}/pulse/pulse.checked"
  ];

  # The verify-then-extract recipe shared by `native` and `bench`.  Verifying
  # into a shared cache in dependency order is what lets the extract step read
  # the dependencies' `.checked` files; one invocation cannot do both (Error
  # 317, "Cross-module inlining expects all modules to be checked first").
  # Each step is bounded by `timeout` so a stuck query dies instead of hanging
  # the build (fstar-codec MANDATES 1-2).
  verify-then-extract = ''
    mkdir -p "$out" cache
    ULIB="${flib}/ulib"
    PULSE_INCS=""
    for d in ${lib.concatStringsSep " " pulse-incs}; do
      PULSE_INCS="$PULSE_INCS --include $d"
    done
    cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
    for m in Data.Codec.Types Data.Codec.Text Data.Codec Data.Codec.Pulse; do
      timeout 600 ${fstar-exe} \
        --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src \
        --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
        --z3rlimit 120 \
        --cache_checked_modules --cache_dir cache --odir cache \
        src/$m.fst || exit 1
    done
    timeout 600 ${fstar-exe} \
      --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src --include cache \
      --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
      --cache_checked_modules --cache_dir cache \
      --codegen C --custard_monomorphize_types true \
      --custard_entry_module Data.Codec.Pulse \
      --custard_c_no_prefix Data.Codec.Pulse \
      --odir "$out" \
      src/Data.Codec.Pulse.fst || exit 1
    cp "$out/Custard.h" "$out/codec.h"
  '';

  native = mkDerivation {
    pname = "${pname}-native";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    inherit meta;
    buildPhase = ''
      ${verify-then-extract}
      # Compile the emitted C11 to a shared object + static lib.
      cc -c -Wall -Wextra -Werror -std=c11 -O2 -fPIC -I $out $out/Custard.c -o $out/Custard.o
      if [ "$(uname -s)" = Darwin ]; then
        cc -dynamiclib $out/Custard.o -o $out/lib${pname}.dylib
      else
        cc -shared $out/Custard.o -o $out/lib${pname}.so
      fi
      ar rcs $out/lib${pname}.a $out/Custard.o
    '';
    installPhase = "true";
  };

  # ── bench (`REQ-ISO-C-PERF`) ─────────────────────────────────────
  #
  # The measurement `REQ-ISO-C-PERF` requires: the extracted C against a
  # hand-written C baseline for the same wire format.  The harness itself lives
  # in `bench/`; this derivation builds and RUNS it, and its output is the
  # recorded figure.  It fails the build if
  #   - either driver fails its roundtrip self-check,
  #   - the two drivers disagree on the sink (same bytes in, same values out), or
  #   - any round is unresolved (a number that came from clock rounding).
  #
  # NOTE on reading `pulse.tsv` / `ref.tsv` from this derivation: a nix build
  # runs in a sandbox, often alongside other builds, so its absolute ps/op are
  # CONTAMINATED (the floor row shows it — it is ~5-10x the quiet-host figure).
  # This target proves the harness BUILDS and RUNS and PASSES its gates; the
  # headline figures in `README.md` come from `bench/run.sh` on a quiet host,
  # which alternates the runs and keeps the minimum.  Use `run.sh` for numbers,
  # this target for "the harness is wired in and self-checking".
  #
  # The pre-tightening side (`32aa8e8^`) is NOT extracted here: a nix build is
  # not in a git repo, so only the current artifact is measured.  `run.sh`, run
  # from a checkout, does both sides for the T9.2 comparison.
  bench = mkDerivation {
    pname = "${pname}-bench";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    inherit meta;
    buildPhase = ''
      mkdir -p $out
      ${verify-then-extract}
      cc -O2 -std=c11 -Wall -Wextra -Werror -I $out \
        -o bench-ref   bench/bench-ref.c
      cc -O2 -std=c11 -Wall -Wextra -Werror -I $out \
        -o bench-pulse bench/bench-pulse.c $out/Custard.c
      ./bench-ref   > ref.tsv   2> ref.err
      ./bench-pulse > pulse.tsv 2> pulse.err
      cat ref.err pulse.err >&2
      grep -q 'roundtrip OK' ref.err   || { echo 'baseline self-check FAILED' >&2; exit 1; }
      grep -q 'roundtrip OK' pulse.err || { echo 'extracted self-check FAILED' >&2; exit 1; }
      test "$(grep -o 'sink=[0-9]*' ref.err)"   = "$(grep -o 'sink=[0-9]*' pulse.err)" \
        || { echo 'baseline and extracted disagree on the sink' >&2; exit 1; }
      awk -F'\t' '!/^#/ && $4 != 0 { exit 1 }' ref.tsv pulse.tsv \
        || { echo 'unresolved rounds — a number came from clock rounding' >&2; exit 1; }
      cp ref.tsv pulse.tsv $out/
    '';
    installPhase = "true";
  };

  # ── F# (.NET) backend ───────────────────────────────────────────────
  #
  # Same flat pattern as `native`: verify → extract F# → compile
  # with `dotnet build` into a .NET library assembly.  Rooted at the codec API
  # (encode_bytes/decode_bytes) so the tuple-returning proof lemmas — which
  # have no F# realization (Error 395) — are not pulled in.

  fsharp = mkDerivation {
    pname = "${pname}-fsharp";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
      dotnet
    ];
    inherit meta;
    buildPhase = ''
      mkdir -p $out cache src-out
      export DOTNET_CLI_TELEMETRY_OPTOUT=1
      export DOTNET_NOLOGO=1
      export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
      export HOME=$NIX_BUILD_TOP
      ULIB="${flib}/ulib"
      PULSE_INCS=""
      for d in ${lib.concatStringsSep " " pulse-incs}; do
        PULSE_INCS="$PULSE_INCS --include $d"
      done
      cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
      for m in Data.Codec.Types Data.Codec.Text Data.Codec Data.Codec.Pulse; do
        ${fstar-exe} \
          --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src \
          --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
          --z3rlimit 120 \
          --cache_checked_modules --cache_dir cache --odir cache \
          src/$m.fst || exit 1
      done
      ${fstar-exe} \
        --no_default_includes --include "$ULIB" $PULSE_INCS --include ./src --include cache \
        --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
        --cache_checked_modules --cache_dir cache \
        --codegen FSharp --custard_monomorphize_types true \
        --custard_entry Data.Codec.Pulse.encode_bytes \
        --custard_entry Data.Codec.Pulse.decode_bytes \
        --odir src-out \
        src/Data.Codec.Pulse.fst || exit 1
      dotnet build src-out/Custard.fsproj -c Release -o $out || exit 1
    '';
    installPhase = "true";
  };

in
{
  inherit
    checked
    ocaml
    native
    fsharp
    bench
    ;
}
