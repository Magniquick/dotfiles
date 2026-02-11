# qs-native

Rust-backed QML plugin (`qsnative`) for Quickshell.

This module is built with CMake + direct Cargo invocation (not Corrosion-managed targets).

## Build

From repo root:

```bash
cmake -S common/modules/qs-native -B common/modules/qs-native/build
cmake --build common/modules/qs-native/build --target qs_native_qml_module_sync
```

This produces:

- Rust shared library: `common/modules/qs-native/build/libqs_native_rust.so`
- QML plugin: `common/modules/qs-native/build/qml/qsnative/libqsnative.so`
- QML metadata: `common/modules/qs-native/build/qml/qsnative/{qmldir,plugin.qmltypes}`

## Useful Targets

- `cargo-build_qs_native_rust`: build Rust crate and copy shared library
- `cargo-clean_qs_native_rust`: clean Rust artifacts under module target dir
- `qs_native_qml_module_sync`: build full plugin and sync QML module files

## Runtime

Set import path to the module `qml` output:

```bash
QML_IMPORT_PATH=~/.config/quickshell/common/modules/qs-native/build/qml quickshell
```

## Notes

- Cargo artifacts are stored in `common/modules/qs-native/build/cargo/build`.
- Helper scripts are profile-aware (`debug` and `release`) via `CARGO_PROFILE_DIR`.
