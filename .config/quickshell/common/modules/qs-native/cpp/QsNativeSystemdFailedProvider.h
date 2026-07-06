#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

struct SystemdFailedHandle;
struct SystemdFailedSnapshotC;

// Failed-systemd-unit provider (system + user scopes). Rust snapshots
// `systemctl [--user] list-units --failed --output=json` on a worker thread
// (`start()`/`refresh()`), then keeps refreshing on a 250ms-debounced timer
// driven by `systemd1` D-Bus manager signals (`scheduleRefresh()` is the
// manual/QML-facing debounce tick). This QObject deep-copies each delivered
// `SystemdFailedSnapshotC` on the Qt thread. All properties update together,
// so a single `changed()` signal drives every binding (QML's per-property
// handlers — onFailed_countChanged, onErrorChanged — fire off it).
class QsNativeSystemdFailedProvider : public QObject {
  Q_OBJECT

  Q_PROPERTY(int system_failed_count READ systemFailedCount NOTIFY changed)
  Q_PROPERTY(int user_failed_count READ userFailedCount NOTIFY changed)
  Q_PROPERTY(int failed_count READ failedCount NOTIFY changed)
  Q_PROPERTY(QVariantList system_failed_units READ systemFailedUnits NOTIFY changed)
  Q_PROPERTY(QVariantList user_failed_units READ userFailedUnits NOTIFY changed)
  Q_PROPERTY(QString last_checked READ lastChecked NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
  Q_PROPERTY(bool refreshing READ refreshing NOTIFY changed)

public:
  explicit QsNativeSystemdFailedProvider(QObject* parent = nullptr);
  ~QsNativeSystemdFailedProvider() override;

  [[nodiscard]] auto systemFailedCount() const -> int { return m_systemFailedCount; }
  [[nodiscard]] auto userFailedCount() const -> int { return m_userFailedCount; }
  [[nodiscard]] auto failedCount() const -> int { return m_failedCount; }
  [[nodiscard]] auto systemFailedUnits() const -> QVariantList { return m_systemFailedUnits; }
  [[nodiscard]] auto userFailedUnits() const -> QVariantList { return m_userFailedUnits; }
  [[nodiscard]] auto lastChecked() const -> QString { return m_lastChecked; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto refreshing() const -> bool { return m_refreshing; }

  Q_INVOKABLE void start();
  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE void scheduleRefresh();

signals:
  void changed();

private:
  static void snapshotCallback(void* ctx, const SystemdFailedSnapshotC* snap);
  void applySnapshot(int systemFailedCount, int userFailedCount, int failedCount,
                     const QVariantList& systemFailedUnits, const QVariantList& userFailedUnits,
                     const QString& lastChecked, const QString& error);

  SystemdFailedHandle* m_handle;

  int m_systemFailedCount = 0;
  int m_userFailedCount = 0;
  int m_failedCount = 0;
  QVariantList m_systemFailedUnits;
  QVariantList m_userFailedUnits;
  QString m_lastChecked;
  QString m_error;
  bool m_refreshing = false;
};
