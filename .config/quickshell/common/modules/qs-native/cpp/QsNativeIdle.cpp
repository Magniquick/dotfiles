#include "QsNativeIdle.h"
#include "qsnative_api.h"

QsNativeIdle::QsNativeIdle(QObject* parent)
    : QObject(parent), m_handle(QsNative_Idle_New()) {}

QsNativeIdle::~QsNativeIdle() {
  QsNative_Idle_Delete(m_handle);
}

auto QsNativeIdle::loadSettings(const QString& path) -> bool {
  const bool ok = QsNative_Idle_LoadSettings(m_handle, path.toUtf8().constData());
  refreshFromSnapshot();
  return ok;
}

auto QsNativeIdle::saveSettings(const QString& path, int displayOffTimeoutSec,
                                int suspendTimeoutSec, bool suspendEnabled,
                                bool ignoreLidEvents) -> bool {
  const bool ok = QsNative_Idle_SaveSettings(m_handle, path.toUtf8().constData(),
                                             displayOffTimeoutSec, suspendTimeoutSec,
                                             suspendEnabled, ignoreLidEvents);
  refreshFromSnapshot();
  return ok;
}

auto QsNativeIdle::clampTimeout(int seconds) const -> int {
  return QsNative_Idle_ClampTimeout(seconds);
}

auto QsNativeIdle::statusJson(bool dpmsOff, double nextSuspendAtMs, bool sleepInhibited,
                              double nowMs) const -> QString {
  char* raw = QsNative_Idle_StatusJson(m_handle, dpmsOff, nextSuspendAtMs, sleepInhibited, nowMs);
  if (raw == nullptr) {
    return {};
  }
  const QString result = QString::fromUtf8(raw);
  QsNative_Free(raw);
  return result;
}

auto QsNativeIdle::syncLidInhibitProcess(bool inhibited) -> bool {
  const bool ok = QsNative_Idle_SyncLidInhibitProcess(m_handle, inhibited);
  refreshFromSnapshot();
  return ok;
}

void QsNativeIdle::snapshotCallback(void* ctx, const IdleSnapshotC* snap) {
  auto* self = static_cast<QsNativeIdle*>(ctx);
  if (snap == nullptr) {
    return;
  }

  // Deep-copy synchronously: the char* field is only valid for this call.
  self->m_displayOffTimeoutSec = snap->display_off_timeout_sec;
  self->m_suspendTimeoutSec = snap->suspend_timeout_sec;
  self->m_suspendEnabled = snap->suspend_enabled;
  self->m_ignoreLidEvents = snap->ignore_lid_events;
  self->m_lidInhibited = snap->lid_inhibited;
  self->m_error = QString::fromUtf8(snap->error);
}

void QsNativeIdle::refreshFromSnapshot() {
  // Synchronous: the callback fires on this (the Qt) thread before returning.
  QsNative_Idle_Snapshot(m_handle, this, &QsNativeIdle::snapshotCallback);
  emit changed();
}
