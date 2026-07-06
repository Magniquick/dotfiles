//! STUB extern-C surface for the `UnifiedLyricsClient` QML type.
//!
//! The C++ Qt glue (`cpp/QsNativeUnifiedLyrics.{h,cpp}`) owns one `QObject` per
//! instance and calls these `extern "C"` functions over an opaque handle.
//!
//! This is a temporary stub: the Spotify/Netease/lrclib fetch pipeline has been
//! removed. `refresh` only validates its inputs and performs no network work, so
//! every QML property stays at its default (lyrics temporarily broken).

use std::ffi::CStr;
use std::os::raw::c_char;

/// Reads a borrowed C string into an owned `String` (empty on null).
///
/// # Safety
/// `ptr` must be null or a valid NUL-terminated string for the call duration.
unsafe fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Opaque per-instance handle owned by the C++ `QsNativeUnifiedLyrics` `QObject`.
// TODO(stage2): carry request-coalescing + qt-thread marshaling state here.
pub struct UnifiedLyricsHandle;

#[no_mangle]
pub extern "C" fn QsNative_UnifiedLyrics_New() -> *mut UnifiedLyricsHandle {
    Box::into_raw(Box::new(UnifiedLyricsHandle))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_UnifiedLyrics_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_UnifiedLyrics_Delete(handle: *mut UnifiedLyricsHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// STUB refresh: validates that a track and artist are present but performs no
/// network fetch. Returns `false` when `track_name` or `artist_name` is empty
/// after trim, `true` otherwise. No properties change.
///
/// # Safety
/// `handle` must be valid; the string args must be null or valid NUL-terminated
/// strings for the duration of the call.
// TODO(stage2): spawn the network workers + 30s watchdog and marshal results
// back onto the Qt thread via a queued callback.
#[no_mangle]
pub unsafe extern "C" fn QsNative_UnifiedLyrics_Refresh(
    handle: *mut UnifiedLyricsHandle,
    spotify_track_ref: *const c_char,
    track_name: *const c_char,
    artist_name: *const c_char,
    album_name: *const c_char,
    length_micros: *const c_char,
) -> bool {
    if handle.is_null() {
        return false;
    }
    let _ = (spotify_track_ref, album_name, length_micros);
    let track_name = c_string(track_name);
    let artist_name = c_string(artist_name);
    !track_name.trim().is_empty() && !artist_name.trim().is_empty()
}
