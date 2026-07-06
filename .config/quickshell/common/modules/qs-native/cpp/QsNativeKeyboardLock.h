#pragma once

#include <QObject>
#include <QString>

struct KeyboardLockHandle;
struct KeyboardLockSnapshotC;

// Caps-lock / num-lock LED watcher. Rust opens the evdev device on a worker
// thread and reports each LED toggle as a zero-copy event struct; this QObject owns
// the observable state and bumps `event_serial` after applying every toggle so
// QML's `onEvent_serialChanged` handler always sees the fresh lock values.
//
// Property names are intentionally snake_case: HudService.qml binds to
// `caps_lock`, `num_lock`, `changed_key`, and `onEvent_serialChanged`.
class QsNativeKeyboardLock : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool running READ running NOTIFY runningChanged)
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString device_path READ devicePath NOTIFY device_pathChanged)
  Q_PROPERTY(bool caps_lock READ capsLock NOTIFY caps_lockChanged)
  Q_PROPERTY(bool num_lock READ numLock NOTIFY num_lockChanged)
  Q_PROPERTY(QString changed_key READ changedKey NOTIFY changed_keyChanged)
  Q_PROPERTY(int event_serial READ eventSerial NOTIFY event_serialChanged)

public:
  explicit QsNativeKeyboardLock(QObject* parent = nullptr);
  ~QsNativeKeyboardLock() override;

  [[nodiscard]] auto running() const -> bool { return m_running; }
  [[nodiscard]] auto available() const -> bool { return m_available; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto devicePath() const -> QString { return m_devicePath; }
  [[nodiscard]] auto capsLock() const -> bool { return m_capsLock; }
  [[nodiscard]] auto numLock() const -> bool { return m_numLock; }
  [[nodiscard]] auto changedKey() const -> QString { return m_changedKey; }
  [[nodiscard]] auto eventSerial() const -> int { return m_eventSerial; }

  Q_INVOKABLE auto start(const QString& path) -> bool;
  Q_INVOKABLE void stop();

signals:
  void runningChanged();
  void availableChanged();
  void errorChanged();
  void device_pathChanged();
  void caps_lockChanged();
  void num_lockChanged();
  void changed_keyChanged();
  void event_serialChanged();

private:
  static void eventCallback(void* ctx, const KeyboardLockSnapshotC* snap);
  void applyEvent(const QString& type, const QString& message, const QString& key,
                  bool enabled);

  void setRunning(bool value);
  void setAvailable(bool value);
  void setError(const QString& value);
  void setDevicePath(const QString& value);
  void setCapsLock(bool value);
  void setNumLock(bool value);
  void setChangedKey(const QString& value);
  void bumpEventSerial();

  KeyboardLockHandle* m_handle;

  bool m_running = false;
  bool m_available = false;
  QString m_error;
  QString m_devicePath;
  bool m_capsLock = false;
  bool m_numLock = false;
  QString m_changedKey;
  int m_eventSerial = 0;
};
