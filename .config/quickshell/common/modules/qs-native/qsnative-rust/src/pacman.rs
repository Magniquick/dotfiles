//! `PacmanUpdatesProvider` backend.
//!
//! Runs `checkupdates` (official repos) and `yay -Qua` (AUR) on a worker
//! thread and delivers a zero-copy `#[repr(C)]` `PacmanSnapshotC` (a borrowed
//! `UpdateItemC` row array plus the aggregate counts/text fields) to the C++
//! `QsNativePacman` `QObject`, which deep-copies it and rebuilds the list
//! model under `beginResetModel`/`endResetModel`. `sync()` fires a detached
//! `sudo -n pacman -Sy --noconfirm` database sync.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::process::{Command, Stdio};
use std::thread;

use chrono::Local;

use crate::count_to_i32;

#[derive(Debug, Clone, PartialEq, Eq)]
struct UpdateItem {
    name: String,
    old_version: String,
    new_version: String,
    source: String,
}

#[derive(Debug, Clone)]
struct UpdatesSnapshot {
    updates: Vec<UpdateItem>,
    updates_count: i32,
    aur_updates_count: i32,
    updates_text: String,
    aur_updates_text: String,
    last_checked: String,
    error: String,
}

#[derive(Debug)]
struct CommandResult {
    status_code: Option<i32>,
    success: bool,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

/// A single resolved update row, borrowed for the duration of the callback.
#[repr(C)]
pub struct UpdateItemC {
    pub name: *const c_char,
    pub old_version: *const c_char,
    pub new_version: *const c_char,
    pub source: *const c_char,
}

/// Zero-copy snapshot handed to the C++ side. `items`/`items_len` describe a
/// borrowed `UpdateItemC` array; the `*const c_char` fields (including the ones
/// nested in each row) borrow `CString`s that live on the worker stack **only
/// for the duration of the callback**. C++ must copy everything
/// (`QString::fromUtf8`) synchronously and must not retain any pointers.
#[repr(C)]
pub struct PacmanSnapshotC {
    pub items: *const UpdateItemC,
    pub items_len: usize,
    pub updates_count: i32,
    pub aur_updates_count: i32,
    pub updates_text: *const c_char,
    pub aur_updates_text: *const c_char,
    pub last_checked: *const c_char,
    pub error: *const c_char,
}

/// Delivers a `PacmanSnapshotC` (borrowed for the call only) to the C++ side.
pub type PacmanSnapshotFn = unsafe extern "C" fn(*mut c_void, *const PacmanSnapshotC);

/// Opaque per-instance handle owned by the C++ `QsNativePacman` `QObject`.
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

/// Kicks off a background refresh (`checkupdates` + optionally `yay -Qua`) and
/// delivers a `PacmanSnapshotC` via `cb`.
///
/// # Safety
/// `handle` must be valid; `ctx`/`cb` must remain valid until `cb` fires.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Pacman_Refresh(
    handle: *mut PacmanHandle,
    no_aur: bool,
    ctx: *mut c_void,
    cb: PacmanSnapshotFn,
) {
    if handle.is_null() {
        return;
    }
    let ctx = ctx as usize;
    thread::spawn(move || {
        let snapshot = refresh_updates(no_aur);

        // CStrings must outlive the callback; keep them bound in this scope.
        let rows: Vec<(CString, CString, CString, CString)> = snapshot
            .updates
            .iter()
            .map(|item| {
                (
                    cstr(&item.name),
                    cstr(&item.old_version),
                    cstr(&item.new_version),
                    cstr(&item.source),
                )
            })
            .collect();
        let items: Vec<UpdateItemC> = rows
            .iter()
            .map(|(name, old_version, new_version, source)| UpdateItemC {
                name: name.as_ptr(),
                old_version: old_version.as_ptr(),
                new_version: new_version.as_ptr(),
                source: source.as_ptr(),
            })
            .collect();
        let updates_text = cstr(&snapshot.updates_text);
        let aur_updates_text = cstr(&snapshot.aur_updates_text);
        let last_checked = cstr(&snapshot.last_checked);
        let error = cstr(&snapshot.error);

        let c = PacmanSnapshotC {
            items: items.as_ptr(),
            items_len: items.len(),
            updates_count: snapshot.updates_count,
            aur_updates_count: snapshot.aur_updates_count,
            updates_text: updates_text.as_ptr(),
            aur_updates_text: aur_updates_text.as_ptr(),
            last_checked: last_checked.as_ptr(),
            error: error.as_ptr(),
        };
        unsafe { cb(ctx as *mut c_void, &raw const c) };
    });
}

/// Kicks off a detached database sync (`sudo -n pacman -Sy --noconfirm`).
///
/// # Safety
/// `handle` must be valid.
#[no_mangle]
pub unsafe extern "C" fn QsNative_Pacman_Sync(handle: *mut PacmanHandle) {
    if handle.is_null() {
        return;
    }
    thread::spawn(|| {
        let _ = run_command("sudo", &["-n", "pacman", "-Sy", "--noconfirm"]);
    });
}

/// Builds a `CString`, falling back to empty on an interior NUL.
fn cstr(value: &str) -> CString {
    CString::new(value).unwrap_or_default()
}

fn refresh_updates(no_aur: bool) -> UpdatesSnapshot {
    let (updates, pacman_error) = check_pacman_updates();
    let (aur_updates, aur_error) = if no_aur {
        (Vec::new(), None)
    } else {
        check_aur_updates()
    };

    let updates_text = update_names(&updates);
    let aur_updates_text = update_names(&aur_updates);
    let updates_count = updates.len();
    let aur_count = aur_updates.len();
    let all_updates: Vec<_> = updates.into_iter().chain(aur_updates).collect();

    let error = [
        pacman_error.map(|error| format!("checkupdates: {error}")),
        aur_error.map(|error| format!("AUR: {error}")),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join("; ");

    UpdatesSnapshot {
        updates: all_updates,
        updates_count: count_to_i32(updates_count),
        aur_updates_count: count_to_i32(aur_count),
        updates_text,
        aur_updates_text,
        last_checked: Local::now().format("%H:%M").to_string(),
        error,
    }
}

fn check_pacman_updates() -> (Vec<UpdateItem>, Option<String>) {
    match run_command("checkupdates", &[]) {
        Ok(output) if output.success => (
            parse_updates_output(&String::from_utf8_lossy(&output.stdout), "pacman"),
            None,
        ),
        Ok(output) if output.status_code == Some(2) => (Vec::new(), None),
        Ok(output) => (Vec::new(), Some(command_failure(&output))),
        Err(error) => (Vec::new(), Some(error)),
    }
}

fn check_aur_updates() -> (Vec<UpdateItem>, Option<String>) {
    match run_command("yay", &["-Qua"]) {
        Ok(output) if output.success => (
            parse_updates_output(&String::from_utf8_lossy(&output.stdout), "aur"),
            None,
        ),
        Ok(output)
            if output.status_code == Some(1)
                && output.stdout.is_empty()
                && output.stderr.is_empty() =>
        {
            (Vec::new(), None)
        }
        Ok(output) => (Vec::new(), Some(command_failure(&output))),
        Err(error) => (Vec::new(), Some(error)),
    }
}

fn parse_updates_output(output: &str, source: &str) -> Vec<UpdateItem> {
    output
        .lines()
        .filter_map(|line| parse_update_line(line, source))
        .collect()
}

fn parse_update_line(line: &str, source: &str) -> Option<UpdateItem> {
    let mut fields = line.split_whitespace();
    let (Some(name), Some(old_version), Some("->"), Some(new_version), None) = (
        fields.next(),
        fields.next(),
        fields.next(),
        fields.next(),
        fields.next(),
    ) else {
        return None;
    };

    Some(UpdateItem {
        name: name.to_owned(),
        old_version: old_version.to_owned(),
        new_version: new_version.to_owned(),
        source: source.to_owned(),
    })
}

fn update_names(items: &[UpdateItem]) -> String {
    items
        .iter()
        .map(|item| item.name.as_str())
        .collect::<Vec<_>>()
        .join("\n")
}

fn run_command(name: &str, args: &[&str]) -> Result<CommandResult, String> {
    let output = Command::new(name)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| error.to_string())?;

    Ok(CommandResult {
        status_code: output.status.code(),
        success: output.status.success(),
        stdout: output.stdout,
        stderr: output.stderr,
    })
}

fn command_failure(output: &CommandResult) -> String {
    let status = output.status_code.map_or_else(
        || "terminated by signal".to_owned(),
        |code| format!("exit status {code}"),
    );
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    if stderr.is_empty() {
        status
    } else {
        format!("{status}: {stderr}")
    }
}

#[cfg(test)]
mod tests {
    use super::{parse_updates_output, UpdateItem};

    #[test]
    fn parses_update_lines_and_ignores_unexpected_shapes() {
        let got = parse_updates_output(
            "linux 6.8.1.arch1-1 -> 6.8.2.arch1-1\nbad 1 => 2\nfoo-bin 1 -> 2\n",
            "aur",
        );

        assert_eq!(
            got,
            vec![
                UpdateItem {
                    name: "linux".to_owned(),
                    old_version: "6.8.1.arch1-1".to_owned(),
                    new_version: "6.8.2.arch1-1".to_owned(),
                    source: "aur".to_owned(),
                },
                UpdateItem {
                    name: "foo-bin".to_owned(),
                    old_version: "1".to_owned(),
                    new_version: "2".to_owned(),
                    source: "aur".to_owned(),
                },
            ]
        );
    }
}
