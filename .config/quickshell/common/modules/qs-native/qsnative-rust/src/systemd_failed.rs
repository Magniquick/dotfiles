//! STUB: `SystemdFailedProvider` on the hand-written `extern "C"` surface.
//!
//! TODO(stage2): restore the real logic — the 250ms-debounced refresh worker,
//! the system + session `systemd1` D-Bus signal listeners, and the
//! `systemctl [--user] list-units --failed --output=json` snapshot parsing.
//! For now every refresh delivers an empty snapshot (0 counts, empty unit
//! lists) so the QML-facing surface stays intact.

use std::os::raw::c_void;

use crate::ffi::{emit_snapshot, QsNativeUpdateFn};

/// Opaque per-instance handle owned by the C++ `QsNativeSystemdFailedProvider`.
///
// TODO(stage2): hold the debounce channel sender + started flag here.
pub struct SystemdFailedHandle {
    _private: (),
}

#[no_mangle]
pub extern "C" fn QsNative_SystemdFailedProvider_New() -> *mut SystemdFailedHandle {
    Box::into_raw(Box::new(SystemdFailedHandle { _private: () }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_SystemdFailedProvider_New`
/// that has not yet been freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_Delete(handle: *mut SystemdFailedHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Delivers a failed-unit snapshot to C++ via `cb`.
///
// TODO(stage2): read the real snapshot on a worker thread; for now emit an
// empty snapshot immediately.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` returns.
#[no_mangle]
pub unsafe extern "C" fn QsNative_SystemdFailedProvider_Refresh(
    handle: *mut SystemdFailedHandle,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) {
    if handle.is_null() {
        return;
    }
    unsafe { emit_snapshot(cb, ctx, empty_snapshot_json()) };
}

/// JSON snapshot delivered to C++; keys match the `SystemdFailedProvider` QML
/// property names. Each `*_failed_units` element (empty here) is an object with
/// string keys: unit, load, active, sub, description.
fn empty_snapshot_json() -> String {
    serde_json::json!({
        "system_failed_count": 0,
        "user_failed_count": 0,
        "failed_count": 0,
        "system_failed_units": [],
        "user_failed_units": [],
        "last_checked": "",
        "error": "",
    })
    .to_string()
}
