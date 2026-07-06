//! Shared C ABI helpers for the hand-written `extern "C"` provider surface.
//!
//! Providers are plain `extern "C"` functions over an opaque handle; the C++
//! Qt glue (`cpp/QsNative*.{h,cpp}`) owns one `QObject` per type and marshals
//! worker-thread updates back onto the Qt thread with a queued invoke.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};

/// Callback used by threaded providers to deliver a JSON snapshot to C++.
///
/// The `json` pointer is borrowed for the duration of the call only: the C++
/// side must copy it (`QString::fromUtf8`) and must **not** free it.
pub type QsNativeUpdateFn = unsafe extern "C" fn(ctx: *mut c_void, json: *const c_char);

/// Converts an owned `String` into a heap `char*` for return across the ABI.
///
/// The returned pointer must be released with `QsNative_Free`.
#[must_use]
#[expect(
    clippy::missing_panics_doc,
    reason = "the fallback CString is built from the byte literal \"{}\", which has no interior NUL, so expect can never fire"
)]
pub fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .unwrap_or_else(|_| CString::new("{}").expect("literal cstring"))
        .into_raw()
}

/// Reads a borrowed C string into an owned `String` (empty on null).
///
/// # Safety
/// `ptr` must be null or a valid NUL-terminated string for the call duration.
#[must_use]
pub unsafe fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Invokes `cb` with `json`, keeping the buffer alive across the call.
///
/// # Safety
/// `cb` and `ctx` must be valid for this invocation.
#[expect(
    clippy::missing_panics_doc,
    reason = "the fallback CString is built from the byte literal \"{}\", which has no interior NUL, so expect can never fire"
)]
pub unsafe fn emit_snapshot(cb: QsNativeUpdateFn, ctx: *mut c_void, json: String) {
    let buf =
        CString::new(json).unwrap_or_else(|_| CString::new("{}").expect("literal cstring"));
    cb(ctx, buf.as_ptr());
}
