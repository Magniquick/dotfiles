//! `PacmanUpdatesProvider` backend (STUB).
//!
//! TODO(stage2): restore the real `checkupdates` / `yay -Qua` refresh and the
//! `sudo -n pacman -Sy` sync. This stub exposes the full extern-C surface so the
//! C++ `QsNativePacman` `QObject` can be wired now; it delivers an empty snapshot
//! on refresh and does nothing on sync.

use std::os::raw::c_void;
use std::thread;

use crate::ffi::{emit_snapshot, QsNativeUpdateFn};

/// Opaque per-instance handle owned by the C++ `QsNativePacman` `QObject`.
// TODO(stage2): carry the shared refresh state (Arc<Mutex<...>>) here.
pub struct PacmanHandle;

#[no_mangle]
pub extern "C" fn QsNative_Pacman_New() -> *mut PacmanHandle {
    Box::into_raw(Box::new(PacmanHandle))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_Pacman_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Pacman_Delete(handle: *mut PacmanHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Kicks off a background refresh and delivers a JSON snapshot via `cb`.
///
/// TODO(stage2): run `checkupdates` + `yay -Qua` here. The stub delivers an
/// empty snapshot so the QML "refresh completed" signals still fire.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Pacman_Refresh(
    handle: *mut PacmanHandle,
    _no_aur: bool,
    ctx: *mut c_void,
    cb: QsNativeUpdateFn,
) {
    if handle.is_null() {
        return;
    }
    let ctx = ctx as usize;
    thread::spawn(move || {
        unsafe { emit_snapshot(cb, ctx as *mut c_void, empty_snapshot_json()) };
    });
}

/// Kicks off a detached database sync.
///
/// TODO(stage2): spawn `sudo -n pacman -Sy --noconfirm`. The stub is a no-op.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Pacman_Sync(handle: *mut PacmanHandle) {
    let _ = handle;
}

/// JSON snapshot with keys matching the C++ `applySnapshot` reader. Empty for
/// the stub: no updates, no error, no timestamp.
fn empty_snapshot_json() -> String {
    serde_json::json!({
        "items": [],
        "updates_count": 0,
        "aur_updates_count": 0,
        "updates_text": "",
        "aur_updates_text": "",
        "last_checked": "",
        "error": "",
    })
    .to_string()
}
