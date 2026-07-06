#include "QsNativeKeyboardLock.h"
#include "qsnative_api.h"

#include <QMetaObject>

QsNativeKeyboardLock::QsNativeKeyboardLock(QObject* parent)
    : QObject(parent), m_handle(QsNative_KeyboardLock_New()) {}

QsNativeKeyboardLock::~QsNativeKeyboardLock() {
  QsNative_KeyboardLock_Delete(m_handle);
}

auto QsNativeKeyboardLock::start(const QString& path) -> bool {
  stop();
  if (path.isEmpty()) {
    setRunning(false);
    setAvailable(false);
    setError(QStringLiteral("keyboard path is empty"));
    return false;
  }

  setError(QString());
  setRunning(true);
  setAvailable(false);
  setDevicePath(path);

  QsNative_KeyboardLock_Start(m_handle, path.toUtf8().constData(), this,
                              &QsNativeKeyboardLock::eventCallback);
  return true;
}

void QsNativeKeyboardLock::stop() {
  QsNative_KeyboardLock_Stop(m_handle);
  setRunning(false);
}

void QsNativeKeyboardLock::eventCallback(void* ctx, const KeyboardLockSnapshotC* snap) {
  auto* self = static_cast<QsNativeKeyboardLock*>(ctx);
  // Deep-copy every field synchronously before the queued invoke; the Rust
  // pointers are only valid for the duration of this callback.
  const QString type = QString::fromUtf8(snap->event_type);
  const QString message = QString::fromUtf8(snap->message);
  const QString key = QString::fromUtf8(snap->key);
  const bool enabled = snap->enabled;
  QMetaObject::invokeMethod(
      self,
      [self, type, message, key, enabled]() { self->applyEvent(type, message, key, enabled); },
      Qt::QueuedConnection);
}

void QsNativeKeyboardLock::applyEvent(const QString& type, const QString& message,
                                      const QString& key, bool enabled) {
  if (type == QStringLiteral("available")) {
    setAvailable(true);
    setError(QString());
  } else if (type == QStringLiteral("error")) {
    setAvailable(false);
    setRunning(false);
    setError(message);
  } else if (type == QStringLiteral("lock")) {
    if (key == QStringLiteral("caps")) {
      setCapsLock(enabled);
      setChangedKey(QStringLiteral("caps"));
    } else if (key == QStringLiteral("num")) {
      setNumLock(enabled);
      setChangedKey(QStringLiteral("num"));
    }
    // Bump last so onEvent_serialChanged observers read the updated lock state.
    bumpEventSerial();
  }
}

void QsNativeKeyboardLock::setRunning(bool value) {
  if (value != m_running) {
    m_running = value;
    emit runningChanged();
  }
}

void QsNativeKeyboardLock::setAvailable(bool value) {
  if (value != m_available) {
    m_available = value;
    emit availableChanged();
  }
}

void QsNativeKeyboardLock::setError(const QString& value) {
  if (value != m_error) {
    m_error = value;
    emit errorChanged();
  }
}

void QsNativeKeyboardLock::setDevicePath(const QString& value) {
  if (value != m_devicePath) {
    m_devicePath = value;
    emit device_pathChanged();
  }
}

void QsNativeKeyboardLock::setCapsLock(bool value) {
  if (value != m_capsLock) {
    m_capsLock = value;
    emit caps_lockChanged();
  }
}

void QsNativeKeyboardLock::setNumLock(bool value) {
  if (value != m_numLock) {
    m_numLock = value;
    emit num_lockChanged();
  }
}

void QsNativeKeyboardLock::setChangedKey(const QString& value) {
  if (value != m_changedKey) {
    m_changedKey = value;
    emit changed_keyChanged();
  }
}

void QsNativeKeyboardLock::bumpEventSerial() {
  // Wrapping i32 increment (avoids signed-overflow UB); always changes so the
  // NOTIFY fires on every toggle even when the lock values repeat.
  m_eventSerial = static_cast<int>(static_cast<unsigned int>(m_eventSerial) + 1U);
  emit event_serialChanged();
}
