#pragma once

#include <QObject>
#include <QString>

struct IdleHandle;
struct IdleSnapshotC;

// Idle/DPMS/suspend settings provider. Rust owns the persisted settings, the
// lid-inhibit child process, and the last error; this QObject mirrors the
// QML-facing properties and refreshes them from a zero-copy `IdleSnapshotC`
// (a #[repr(C)] struct) after every mutating invokable. Fully synchronous: no
// worker threads, so the snapshot callback fires on the Qt thread.
class QsNativeIdle : public QObject {
  Q_OBJECT

  Q_PROPERTY(int displayOffTimeoutSec READ displayOffTimeoutSec NOTIFY changed)
  Q_PROPERTY(int suspendTimeoutSec READ suspendTimeoutSec NOTIFY changed)
  Q_PROPERTY(bool suspendEnabled READ suspendEnabled NOTIFY changed)
  Q_PROPERTY(bool ignoreLidEvents READ ignoreLidEvents NOTIFY changed)
  Q_PROPERTY(bool lidInhibited READ lidInhibited NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)

public:
  explicit QsNativeIdle(QObject* parent = nullptr);
  ~QsNativeIdle() override;

  [[nodiscard]] auto displayOffTimeoutSec() const -> int { return m_displayOffTimeoutSec; }
  [[nodiscard]] auto suspendTimeoutSec() const -> int { return m_suspendTimeoutSec; }
  [[nodiscard]] auto suspendEnabled() const -> bool { return m_suspendEnabled; }
  [[nodiscard]] auto ignoreLidEvents() const -> bool { return m_ignoreLidEvents; }
  [[nodiscard]] auto lidInhibited() const -> bool { return m_lidInhibited; }
  [[nodiscard]] auto error() const -> QString { return m_error; }

  Q_INVOKABLE auto loadSettings(const QString& path) -> bool;
  Q_INVOKABLE auto saveSettings(const QString& path, int displayOffTimeoutSec,
                                int suspendTimeoutSec, bool suspendEnabled,
                                bool ignoreLidEvents) -> bool;
  Q_INVOKABLE [[nodiscard]] auto clampTimeout(int seconds) const -> int;
  Q_INVOKABLE [[nodiscard]] auto statusJson(bool dpmsOff, double nextSuspendAtMs,
                                            bool sleepInhibited, double nowMs) const -> QString;
  Q_INVOKABLE auto syncLidInhibitProcess(bool inhibited) -> bool;

signals:
  void changed();

private:
  static void snapshotCallback(void* ctx, const IdleSnapshotC* snap);
  void refreshFromSnapshot();

  IdleHandle* m_handle;

  int m_displayOffTimeoutSec = 10;
  int m_suspendTimeoutSec = 1800;
  bool m_suspendEnabled = false;
  bool m_ignoreLidEvents = false;
  bool m_lidInhibited = false;
  QString m_error;
};
