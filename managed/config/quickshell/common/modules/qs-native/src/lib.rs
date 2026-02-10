use std::pin::Pin;

mod ai;
mod backlight;
mod ical;
mod pacman;
mod sysinfo;
mod todoist;
mod util;

use chrono::{DateTime, Utc};
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Instant;

#[derive(Default)]
pub struct IcalCacheRust {
  status: cxx_qt_lib::QString,
  generated_at: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  events_json: cxx_qt_lib::QString,
  meta_by_url: HashMap<String, ical::CacheMeta>,
  ics_by_url: HashMap<String, String>,
}

#[derive(Default)]
pub struct TodoistClientRust {
  data_json: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  last_updated: cxx_qt_lib::QString,
}

pub struct SysInfoProviderRust {
  cpu: f64,
  mem: i32,
  mem_used: cxx_qt_lib::QString,
  mem_total: cxx_qt_lib::QString,
  disk: i32,
  disk_health: cxx_qt_lib::QString,
  disk_wear: cxx_qt_lib::QString,
  temp: f64,
  uptime: cxx_qt_lib::QString,
  psi_cpu_some: f64,
  psi_cpu_full: f64,
  psi_mem_some: f64,
  psi_mem_full: f64,
  psi_io_some: f64,
  psi_io_full: f64,
  disk_device: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  last_cpu_total: u64,
  last_cpu_idle: u64,
  last_disk_health_at: Option<Instant>,
  disk_health_cache: String,
  disk_wear_cache: String,
}

#[derive(Default)]
pub struct PacmanUpdatesProviderRust {
  updates_count: i32,
  aur_updates_count: i32,
  updates_text: cxx_qt_lib::QString,
  aur_updates_text: cxx_qt_lib::QString,
  last_checked: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  has_updates: bool,
}

#[derive(Default)]
pub struct BacklightProviderRust {
  available: bool,
  device: cxx_qt_lib::QString,
  brightness_percent: i32,
  error: cxx_qt_lib::QString,

  // Rust-only cache; we still re-discover device for set() to avoid stale paths.
  sysfs_dir: Option<PathBuf>,
  max_brightness: i64,
}

#[derive(Default)]
pub struct AiChatSessionRust {
  model_id: cxx_qt_lib::QString,
  system_prompt: cxx_qt_lib::QString,
  openai_api_key: cxx_qt_lib::QString,
  gemini_api_key: cxx_qt_lib::QString,
  openai_base_url: cxx_qt_lib::QString,

  busy: bool,
  status: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  messages_json: cxx_qt_lib::QString,

  // Rust-only state
  messages: Vec<ai::ChatMessage>,
  id_counter: u64,
  http_client: Option<rig::http_client::ReqwestClient>,
  openai_cache: Option<ai::OpenAiCache>,
  gemini_cache: Option<ai::GeminiCache>,
  last_request_at: Option<DateTime<Utc>>,
  last_success_at: Option<DateTime<Utc>>,
  last_error_at: Option<DateTime<Utc>>,
  last_latency_ms: Option<u128>,
  last_verify_at: Option<DateTime<Utc>>,
  last_verify_ok: Option<bool>,
  last_verify_latency_ms: Option<u128>,
}

#[derive(Default)]
pub struct AiModelCatalogRust {
  openai_api_key: cxx_qt_lib::QString,
  gemini_api_key: cxx_qt_lib::QString,
  openai_base_url: cxx_qt_lib::QString,
  busy: bool,
  status: cxx_qt_lib::QString,
  error: cxx_qt_lib::QString,
  models_json: cxx_qt_lib::QString,
}

#[cxx_qt::bridge]
mod qobjects {
  unsafe extern "C++" {
    include!("cxx-qt-lib/qstring.h");
    type QString = cxx_qt_lib::QString;

    include!("cxx-qt-lib/qmodelindex.h");
    type QModelIndex = cxx_qt_lib::QModelIndex;

    include!("cxx-qt-lib/qvariant.h");
    type QVariant = cxx_qt_lib::QVariant;

    include!("cxx-qt-lib/qbytearray.h");
    type QByteArray = cxx_qt_lib::QByteArray;

    include!("cxx-qt-lib/qhash_i32_QByteArray.h");
    type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;

    include!("cxx-qt-lib/core/qlist/qlist_i32.h");
    type QList_i32 = cxx_qt_lib::QList<i32>;

    include!(<QtCore/QAbstractListModel>);
    type QAbstractListModel;
  }

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(QString, status)]
    #[qproperty(QString, generated_at)]
    #[qproperty(QString, error)]
    #[qproperty(QString, events_json)]
    #[namespace = "qs_native"]
    type IcalCache = super::IcalCacheRust;
  }

  impl cxx_qt::Threading for IcalCache {}

  extern "RustQt" {
    #[qinvokable]
    #[cxx_name = "refreshFromEnv"]
    fn refresh_from_env(self: Pin<&mut IcalCache>, env_file: &QString, days: i32);
  }

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(QString, data_json)]
    #[qproperty(QString, error)]
    #[qproperty(QString, last_updated)]
    #[namespace = "qs_native"]
    type TodoistClient = super::TodoistClientRust;
  }

  extern "RustQt" {
    #[qinvokable]
    #[cxx_name = "listTasks"]
    fn list_tasks(self: Pin<&mut TodoistClient>, env_file: &QString) -> bool;

    #[qinvokable]
    #[cxx_name = "listTasklists"]
    fn list_tasklists(self: Pin<&mut TodoistClient>, env_file: &QString) -> bool;

    #[qinvokable]
    #[cxx_name = "completeTask"]
    fn complete_task(self: Pin<&mut TodoistClient>, env_file: &QString, id: &QString) -> bool;

    #[qinvokable]
    #[cxx_name = "deleteTask"]
    fn delete_task(self: Pin<&mut TodoistClient>, env_file: &QString, id: &QString) -> bool;
  }

  impl cxx_qt::Threading for TodoistClient {}

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(f64, cpu)]
    #[qproperty(i32, mem)]
    #[qproperty(QString, mem_used)]
    #[qproperty(QString, mem_total)]
    #[qproperty(i32, disk)]
    #[qproperty(QString, disk_health)]
    #[qproperty(QString, disk_wear)]
    #[qproperty(f64, temp)]
    #[qproperty(QString, uptime)]
    #[qproperty(f64, psi_cpu_some)]
    #[qproperty(f64, psi_cpu_full)]
    #[qproperty(f64, psi_mem_some)]
    #[qproperty(f64, psi_mem_full)]
    #[qproperty(f64, psi_io_some)]
    #[qproperty(f64, psi_io_full)]
    #[qproperty(QString, disk_device)]
    #[qproperty(QString, error)]
    #[namespace = "qs_native"]
    type SysInfoProvider = super::SysInfoProviderRust;
  }

  extern "RustQt" {
    #[qinvokable]
    fn refresh(self: Pin<&mut SysInfoProvider>) -> bool;
  }

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(i32, updates_count)]
    #[qproperty(i32, aur_updates_count)]
    #[qproperty(QString, updates_text)]
    #[qproperty(QString, aur_updates_text)]
    #[qproperty(QString, last_checked)]
    #[qproperty(QString, error)]
    #[qproperty(bool, has_updates)]
    #[namespace = "qs_native"]
    type PacmanUpdatesProvider = super::PacmanUpdatesProviderRust;
  }

  extern "RustQt" {
    #[qinvokable]
    fn refresh(self: Pin<&mut PacmanUpdatesProvider>, no_aur: bool) -> bool;

    #[qinvokable]
    fn sync(self: Pin<&mut PacmanUpdatesProvider>) -> bool;
  }

  impl cxx_qt::Threading for PacmanUpdatesProvider {}

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(bool, available)]
    #[qproperty(QString, device)]
    #[qproperty(i32, brightness_percent)]
    #[qproperty(QString, error)]
    #[namespace = "qs_native"]
    type BacklightProvider = super::BacklightProviderRust;
  }

  extern "RustQt" {
    #[qinvokable]
    fn start(self: Pin<&mut BacklightProvider>) -> bool;

    #[qinvokable]
    fn refresh(self: Pin<&mut BacklightProvider>) -> bool;

    #[qinvokable]
    #[cxx_name = "setBrightness"]
    fn set_brightness(self: Pin<&mut BacklightProvider>, percent: i32) -> bool;
  }

  impl cxx_qt::Threading for BacklightProvider {}

  extern "RustQt" {
    #[qobject]
    #[base = QAbstractListModel]
    #[qml_element]
    #[qproperty(QString, model_id)]
    #[qproperty(QString, system_prompt)]
    #[qproperty(QString, openai_api_key)]
    #[qproperty(QString, gemini_api_key)]
    #[qproperty(QString, openai_base_url)]
    #[qproperty(bool, busy)]
    #[qproperty(QString, status)]
    #[qproperty(QString, error)]
    #[qproperty(QString, messages_json)]
    #[namespace = "qs_native"]
    type AiChatSession = super::AiChatSessionRust;
  }

  unsafe extern "RustQt" {
    #[cxx_name = "rowCount"]
    #[cxx_override]
    fn row_count(self: &AiChatSession, parent: &QModelIndex) -> i32;

    #[cxx_override]
    fn data(self: &AiChatSession, index: &QModelIndex, role: i32) -> QVariant;

    #[cxx_name = "roleNames"]
    #[cxx_override]
    fn role_names(self: &AiChatSession) -> QHash_i32_QByteArray;

    #[inherit]
    #[cxx_name = "beginInsertRows"]
    fn begin_insert_rows(self: Pin<&mut AiChatSession>, parent: &QModelIndex, first: i32, last: i32);
    #[inherit]
    #[cxx_name = "endInsertRows"]
    fn end_insert_rows(self: Pin<&mut AiChatSession>);

    #[inherit]
    #[cxx_name = "beginRemoveRows"]
    fn begin_remove_rows(self: Pin<&mut AiChatSession>, parent: &QModelIndex, first: i32, last: i32);
    #[inherit]
    #[cxx_name = "endRemoveRows"]
    fn end_remove_rows(self: Pin<&mut AiChatSession>);

    #[inherit]
    #[cxx_name = "beginResetModel"]
    fn begin_reset_model(self: Pin<&mut AiChatSession>);
    #[inherit]
    #[cxx_name = "endResetModel"]
    fn end_reset_model(self: Pin<&mut AiChatSession>);

    #[inherit]
    #[cxx_name = "index"]
    fn index_for_row(self: &AiChatSession, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex;

    #[inherit]
    #[cxx_name = "dataChanged"]
    fn data_changed(self: Pin<&mut AiChatSession>, top_left: &QModelIndex, bottom_right: &QModelIndex, roles: &QList_i32);
  }

  unsafe extern "RustQt" {
    #[qsignal]
    #[cxx_name = "openModelPickerRequested"]
    fn open_model_picker_requested(self: Pin<&mut AiChatSession>);

    #[qsignal]
    #[cxx_name = "openMoodPickerRequested"]
    fn open_mood_picker_requested(self: Pin<&mut AiChatSession>);

    #[qsignal]
    #[cxx_name = "scrollToEndRequested"]
    fn scroll_to_end_requested(self: Pin<&mut AiChatSession>);

    #[qsignal]
    #[cxx_name = "copyAllRequested"]
    fn copy_all_requested(self: Pin<&mut AiChatSession>, text: QString);
  }

  extern "RustQt" {
    #[qinvokable]
    #[cxx_name = "submitInput"]
    fn submit_input(self: Pin<&mut AiChatSession>, text: &QString);

    #[qinvokable]
    #[cxx_name = "submitInputWithAttachments"]
    fn submit_input_with_attachments(
      self: Pin<&mut AiChatSession>,
      text: &QString,
      attachments_json: &QString,
    );

    #[qinvokable]
    #[cxx_name = "pasteImageFromClipboard"]
    fn paste_image_from_clipboard(self: Pin<&mut AiChatSession>) -> QString;

    #[qinvokable]
    #[cxx_name = "pasteAttachmentFromClipboard"]
    fn paste_attachment_from_clipboard(self: Pin<&mut AiChatSession>) -> QString;

    #[qinvokable]
    #[cxx_name = "regenerate"]
    fn regenerate(self: Pin<&mut AiChatSession>, message_id: &QString);

    #[qinvokable]
    #[cxx_name = "deleteMessage"]
    fn delete_message(self: Pin<&mut AiChatSession>, message_id: &QString);

    #[qinvokable]
    #[cxx_name = "editMessage"]
    fn edit_message(self: Pin<&mut AiChatSession>, message_id: &QString, new_body: &QString);

    #[qinvokable]
    #[cxx_name = "resetForModelSwitch"]
    fn reset_for_model_switch(self: Pin<&mut AiChatSession>, model_id: &QString);

    #[qinvokable]
    #[cxx_name = "appendInfo"]
    fn append_info(self: Pin<&mut AiChatSession>, text: &QString);

    #[qinvokable]
    #[cxx_name = "copyAllText"]
    fn copy_all_text(self: Pin<&mut AiChatSession>) -> QString;
  }

  impl cxx_qt::Threading for AiChatSession {}

  extern "RustQt" {
    #[qobject]
    #[qml_element]
    #[qproperty(QString, openai_api_key)]
    #[qproperty(QString, gemini_api_key)]
    #[qproperty(QString, openai_base_url)]
    #[qproperty(bool, busy)]
    #[qproperty(QString, status)]
    #[qproperty(QString, error)]
    #[qproperty(QString, models_json)]
    #[namespace = "qs_native"]
    type AiModelCatalog = super::AiModelCatalogRust;
  }

  extern "RustQt" {
    #[qinvokable]
    fn refresh(self: Pin<&mut AiModelCatalog>) -> bool;
  }

  impl cxx_qt::Threading for AiModelCatalog {}
}
