//! Streaming markdown block model — STAGE-1 STUB.
//!
//! Ported off cxx-qt to a hand-written `extern "C"` surface over an opaque
//! handle. The C++ `QsNativeMarkdownStream` `QObject` (a `QAbstractListModel`
//! registered in QML as `MarkdownStreamModel`) owns one handle and calls these
//! functions.
//!
//! TODO(stage2): reinstate the real `mdstream` incremental parser (delta diff,
//! block commit, code-fence extraction, math repair) behind this same C ABI.
//! For now every call is a no-op and the model reports zero rows.

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

/// Opaque per-instance handle owned by the C++ `QsNativeMarkdownStream` `QObject`.
///
/// TODO(stage2): hold the real `MdStream` / `DocumentState` and the parsed rows.
pub struct MarkdownStreamHandle {
    // Retained so stage-2 can diff incoming full-text feeds; unused in the stub.
    content: String,
    streaming: bool,
}

#[no_mangle]
pub extern "C" fn QsNative_MarkdownStream_New() -> *mut MarkdownStreamHandle {
    Box::into_raw(Box::new(MarkdownStreamHandle {
        content: String::new(),
        streaming: true,
    }))
}

/// # Safety
/// `handle` must be null or a pointer from `QsNative_MarkdownStream_New` not yet freed.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_Delete(handle: *mut MarkdownStreamHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

/// Feeds the full content text and returns the resulting block count.
///
/// TODO(stage2): re-parse (delta append or reset) and return the real count.
///
/// # Safety
/// `handle` must be valid; `content` must be null or a valid C string.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_SetContent(
    handle: *mut MarkdownStreamHandle,
    content: *const c_char,
) -> i32 {
    if handle.is_null() {
        return 0;
    }
    (*handle).content = c_string(content);
    0
}

/// Sets streaming mode and returns the resulting block count.
///
/// TODO(stage2): finalize the pending block when `streaming` becomes false.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_SetStreaming(
    handle: *mut MarkdownStreamHandle,
    streaming: bool,
) -> i32 {
    if handle.is_null() {
        return 0;
    }
    (*handle).streaming = streaming;
    0
}

/// Commits the pending block and returns the resulting block count.
///
/// TODO(stage2): call `stream.finalize()` + refresh.
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_MarkdownStream_Finalize(
    handle: *mut MarkdownStreamHandle,
) -> i32 {
    let _ = handle;
    0
}
