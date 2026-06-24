use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

/// Atomically writes `data` to `path` via a temporary file in the same directory.
///
/// - `fsync`: if `true`, calls `sync_all()` on the temp file before renaming.
/// - `mode`: if `Some(m)`, sets Unix permissions to `m` before renaming.
///
/// The directory is created if it does not already exist.
pub(crate) fn write_file_atomic(
    path: &Path,
    data: &[u8],
    fsync: bool,
    mode: Option<u32>,
) -> Result<(), String> {
    let dir = path
        .parent()
        .ok_or_else(|| "path has no parent".to_owned())?;
    fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(dir).map_err(|error| error.to_string())?;
    file.write_all(data).map_err(|error| error.to_string())?;
    if let Some(m) = mode {
        file.as_file()
            .set_permissions(PermissionsExt::from_mode(m))
            .map_err(|error| error.to_string())?;
    }
    if fsync {
        file.as_file()
            .sync_all()
            .map_err(|error| error.to_string())?;
    }
    file.persist(path)
        .map(|_| ())
        .map_err(|error| error.error.to_string())
}

/// Builds a multi-threaded Tokio runtime with all I/O and time drivers enabled.
pub(crate) fn build_multi_thread_runtime() -> Result<tokio::runtime::Runtime, String> {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .map_err(|e| e.to_string())
}

/// Returns `true` when `value` is `false`.
///
/// Intended for use with `#[serde(skip_serializing_if = "crate::utils::is_false")]`.
pub fn is_false(value: &bool) -> bool {
    !*value
}

/// Trims `value` and returns `Some(trimmed.to_owned())` if non-empty, else `None`.
pub(crate) fn non_empty_trimmed(value: &str) -> Option<String> {
    let trimmed = value.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

/// Trims each candidate and returns the first non-empty one, or an empty `String`.
pub(crate) fn first_non_empty<const N: usize>(values: [&str; N]) -> String {
    values
        .into_iter()
        .map(str::trim)
        .find(|value| !value.is_empty())
        .unwrap_or_default()
        .to_owned()
}
