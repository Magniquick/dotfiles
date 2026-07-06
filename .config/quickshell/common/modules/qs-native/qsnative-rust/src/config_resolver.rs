//! `ConfigResolver` provider (STUB).
//!
//! TODO(stage2): restore the real config/secret resolution. The QML-facing
//! surface (`values` `QVariantMap` property + `refresh()` invokable) is preserved,
//! but `refresh()` currently produces an empty map, so AI provider config/keys
//! are temporarily unavailable.

use std::os::raw::c_char;

use crate::ffi::into_c_string;

/// Canonical default model id, still consumed by `chatstore` for new
/// conversations. Kept even though the resolver body is stubbed.
pub(crate) const DEFAULT_MODEL: &str = "local/gpt-5.4-mini";

/// Opaque per-instance handle owned by the C++ `QsNativeConfigResolver` `QObject`.
pub struct ConfigResolverHandle;

#[no_mangle]
pub extern "C" fn QsNative_ConfigResolver_New() -> *mut ConfigResolverHandle {
    Box::into_raw(Box::new(ConfigResolverHandle))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_ConfigResolver_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_ConfigResolver_Delete(handle: *mut ConfigResolverHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Resolves the current config/secret values as a JSON object (string -> string).
///
/// TODO(stage2): reload `config.toml` and overlay Secret Service keys. For now
/// this returns an empty object; the returned pointer must be freed with
/// `QsNative_Free`.
///
/// # Safety
/// `handle` must be valid; the returned pointer must be released with `QsNative_Free`.
#[no_mangle]
pub unsafe extern "C" fn QsNative_ConfigResolver_Refresh(
    handle: *mut ConfigResolverHandle,
) -> *mut c_char {
    if handle.is_null() {
        return into_c_string("{}".to_owned());
    }
    // TODO(stage2): produce OPENAI_MODEL, *_BASE_URL, and secret keys here.
    into_c_string("{}".to_owned())
}
