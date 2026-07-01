# Shared CXX-Qt Build

This directory is the grouped CMake entry point for Rust/CXX-Qt modules:

- `../qs-native`
- `../material-popups`
- `../qsmath`

The Cargo workspace manifest lives one level up at `../Cargo.toml` because
Cargo requires workspace members to be below the workspace root.

Build through the existing per-module scripts from the Quickshell config root:

```sh
bash tools/build-qs-native.sh
bash tools/build-material-popups.sh
bash tools/build-qsmath.sh
```

Those scripts configure this project at `common/modules/cxxqt/build`, build only
the requested module target, and keep each old import path available as
`common/modules/<module>/build/qml` via a `build` symlink to the grouped
sub-build.

Cargo output shared by the grouped modules lives under
`common/modules/cxxqt/build/cargo/build`.

Rust builds run through one workspace Cargo invocation from this grouped CMake
project. CXX-Qt/Corrosion is still fetched here for the CXX-Qt CMake support,
but module targets link the workspace-built static archives directly to avoid
Corrosion's per-package `cargo rustc` targets.

Rust linting:

```sh
bash tools/rust-lint.sh
```

That script runs workspace-level `cargo fmt --check` and release-mode
`cargo clippy` against the same shared Cargo target directory as the CMake
build. Avoid direct debug `cargo clippy` runs unless you intentionally want a
separate debug cache.

Cleanup:

```sh
bash tools/rust-clean.sh
bash tools/rust-clean.sh --full
```

Use `--full` when CMake state, generated CXX-Qt headers, or the per-module
`build` symlinks need to be recreated from scratch.
