use core::pin::Pin;
use std::process::{Command, Stdio};
use std::thread;

use chrono::Local;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QModelIndex, QString, QVariant};

use crate::count_to_i32;

const NAME_ROLE: i32 = 0x0101;
const OLD_VERSION_ROLE: i32 = 0x0102;
const NEW_VERSION_ROLE: i32 = 0x0103;
const SOURCE_ROLE: i32 = 0x0104;

#[derive(Default)]
pub struct PacmanUpdatesProviderRust {
    updates_count: i32,
    aur_updates_count: i32,
    items_count: i32,
    updates_text: QString,
    aur_updates_text: QString,
    last_checked: QString,
    has_updates: bool,
    error: QString,
    items: Vec<UpdateItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct UpdateItem {
    name: String,
    old_version: String,
    new_version: String,
    source: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++Qt" {
        include!("QtCore/QAbstractListModel");
        #[qobject]
        type QAbstractListModel;
    }

    unsafe extern "C++" {
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
        include!("cxx-qt-lib/qhash_i32_QByteArray.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    impl cxx_qt::Threading for PacmanUpdatesProvider {}

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[base = QAbstractListModel]
        #[qproperty(i32, updates_count, cxx_name = "updates_count")]
        #[qproperty(i32, aur_updates_count, cxx_name = "aur_updates_count")]
        #[qproperty(i32, items_count, cxx_name = "items_count")]
        #[qproperty(QString, updates_text, cxx_name = "updates_text")]
        #[qproperty(QString, aur_updates_text, cxx_name = "aur_updates_text")]
        #[qproperty(QString, last_checked, cxx_name = "last_checked")]
        #[qproperty(bool, has_updates, cxx_name = "has_updates")]
        #[qproperty(QString, error)]
        type PacmanUpdatesProvider = super::PacmanUpdatesProviderRust;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &PacmanUpdatesProvider, parent: &QModelIndex) -> i32;

        #[qinvokable]
        #[cxx_override]
        fn data(self: &PacmanUpdatesProvider, index: &QModelIndex, role: i32) -> QVariant;

        #[qinvokable]
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &PacmanUpdatesProvider) -> QHash_i32_QByteArray;

        #[qinvokable]
        fn refresh(self: Pin<&mut PacmanUpdatesProvider>, no_aur: bool) -> bool;

        #[qinvokable]
        fn sync(self: Pin<&mut PacmanUpdatesProvider>) -> bool;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        unsafe fn begin_reset_model(self: Pin<&mut PacmanUpdatesProvider>);

        #[inherit]
        #[cxx_name = "endResetModel"]
        unsafe fn end_reset_model(self: Pin<&mut PacmanUpdatesProvider>);
    }

    impl cxx_qt::Initialize for PacmanUpdatesProvider {}
}

impl cxx_qt::Initialize for ffi::PacmanUpdatesProvider {
    fn initialize(self: Pin<&mut Self>) {}
}

impl ffi::PacmanUpdatesProvider {
    pub fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() {
            0
        } else {
            count_to_i32(self.rust().items.len())
        }
    }

    pub fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        if !index.is_valid() || index.column() != 0 {
            return QVariant::default();
        }
        let row = index.row();
        if row < 0 {
            return QVariant::default();
        }
        let Some(item) = self.rust().items.get(row as usize) else {
            return QVariant::default();
        };

        match role {
            NAME_ROLE => QVariant::from(&QString::from(item.name.as_str())),
            OLD_VERSION_ROLE => QVariant::from(&QString::from(item.old_version.as_str())),
            NEW_VERSION_ROLE => QVariant::from(&QString::from(item.new_version.as_str())),
            SOURCE_ROLE => QVariant::from(&QString::from(item.source.as_str())),
            _ => QVariant::default(),
        }
    }

    pub fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        roles.insert_clone(&NAME_ROLE, &QByteArray::from("name"));
        roles.insert_clone(&OLD_VERSION_ROLE, &QByteArray::from("old_version"));
        roles.insert_clone(&NEW_VERSION_ROLE, &QByteArray::from("new_version"));
        roles.insert_clone(&SOURCE_ROLE, &QByteArray::from("source"));
        roles
    }

    pub fn refresh(self: Pin<&mut Self>, no_aur: bool) -> bool {
        let qt_thread = self.as_ref().qt_thread();
        thread::spawn(move || {
            let snapshot = refresh_updates(no_aur);
            let _ = qt_thread.queue(move |mut provider| {
                provider.as_mut().apply_snapshot(snapshot);
            });
        });
        true
    }

    pub fn sync(self: Pin<&mut Self>) -> bool {
        thread::spawn(|| {
            let _ = run_command("sudo", &["-n", "pacman", "-Sy", "--noconfirm"]);
        });
        true
    }

    fn apply_snapshot(mut self: Pin<&mut Self>, snapshot: UpdatesSnapshot) {
        let item_count = count_to_i32(snapshot.updates.len());

        unsafe {
            self.as_mut().begin_reset_model();
            self.as_mut().rust_mut().as_mut().get_mut().items = snapshot.updates;
            self.as_mut().end_reset_model();
        }

        self.as_mut().set_updates_count(snapshot.updates_count);
        self.as_mut()
            .set_aur_updates_count(snapshot.aur_updates_count);
        self.as_mut().set_items_count(item_count);
        self.as_mut()
            .set_updates_text(QString::from(snapshot.updates_text));
        self.as_mut()
            .set_aur_updates_text(QString::from(snapshot.aur_updates_text));
        self.as_mut()
            .set_last_checked(QString::from(snapshot.last_checked));
        self.as_mut().set_has_updates(item_count > 0);
        self.set_error(QString::from(snapshot.error));
    }
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
