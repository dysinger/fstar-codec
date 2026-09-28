# fstar-codec Backend Extraction Specification

> Version: 0.1.0
> Updated: 2026-09-27

## Purpose

`fstar-codec` SHALL compile its C-extractable `Data.Codec.Pulse` module to C
(`native`), Rust (`rust`), and WebAssembly (`wasm`), and its pure spec modules
to OCaml (`ocaml`), in addition to verifying (`checked`) and extracting KaRaMeL
IR (`krml`).

## ADDED Requirements

### Requirement: Native C shared library

**ID**: REQ-CODEC-001
**Priority**: P1
The build SHALL produce a native C shared library from `Data.Codec.Pulse`.

#### Scenario: Link succeeds on macOS

- **GIVEN** the fstar/karamel toolchain and `Data_Codec_Pulse.krml`
- **WHEN** `nix build .#fstar-codec-native` runs
- **THEN** KaRaMeL emits `Data_Codec_Pulse.c`/`.h` without fatal warnings
- **AND** the C link resolves all `Prims_*`/`FStar_*` runtime symbols
- **AND** `libfstar-codec.dylib` (macOS) or `libfstar-codec.so` (Linux) is produced

#### Scenario: No fatal Warning 2

- **GIVEN** `Data.Codec.Pulse` uses `FStar.UInt8.uint_to_t`
- **WHEN** KaRaMeL compiles it to C
- **THEN** the build SHALL apply `-warn-error -2` so "function without C
  implementation" is non-fatal
- **AND** the runtime symbol is supplied by `libkrmllib.a` at link time

### Requirement: Rust library

**ID**: REQ-CODEC-002
**Priority**: P1
The build SHALL produce a Rust rlib from `Data.Codec.Pulse`.

#### Scenario: rlib produced

- **GIVEN** `Data.Codec.Pulse` narrowed so it does not reach `FStar.List`
- **WHEN** `nix build .#fstar-codec-rust` runs
- **THEN** `rustc` produces `libfstar-codec.rlib`
- **AND** the crate name is underscored and the filename hyphenated

### Requirement: WebAssembly module

**ID**: REQ-CODEC-003
**Priority**: P1
The build SHALL produce a wasm module from `Data.Codec.Pulse`.

#### Scenario: wasm magic valid

- **GIVEN** `Data.Codec.Pulse` narrowed so it does not reach `FStar.List`
- **WHEN** `nix build .#fstar-codec-wasm` runs
- **THEN** the `.wasm` begins with `\x00asm`
- **AND** no `FStar.List.Tot.Base.tail` unrecoverable error occurs

### Requirement: C-extractable module does not reach FStar.List

**ID**: REQ-CODEC-004
**Priority**: P1
`Data.Codec.Pulse` SHALL NOT `open` the pure `Data.Codec.Types` module.

#### Scenario: no list reachability

- **GIVEN** `Data.Codec.Pulse` previously `open Data.Codec.Types`
- **WHEN** the `open` is narrowed to `byte`/`byte_seq` aliases + ghost `byte_val`
- **THEN** `Data_Codec_Pulse.krml` extraction closure SHALL NOT contain
  `FStar.List.Tot.Base`
- **AND** the module SHALL still verify at 0 admits

## Technical Notes

- **Implementation**: `src/Data.Codec.Pulse.fst`, `default.nix`, `Makefile`
- **Reference KaRaMeL flags**: monorepo `tls/Makefile` (`-warn-error -2 -warn-error -9-16 -warn-error -11 -warn-error -26..28 -no-prefix` + `libkrmllib.a` link)
- **Dependencies**: `fstar`, `karamel`, `fstar-krml` (krmllib C runtime), `rustc`, `ocamlPackages`
