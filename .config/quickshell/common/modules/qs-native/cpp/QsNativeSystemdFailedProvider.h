#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

struct SystemdFailedHandle;

// STUB: failed-systemd-unit provider. Rust currently delivers an empty snapshot
// per refresh; this QObject applies it on the Qt thread. All properties update
// together, so a single `changed()` signal drives every binding (QML's
// per-property handlers — onFailed_countChanged, onErrorChanged — fire off it).
//
// TODO(stage2): restore the debounce worker + systemd D-Bus listeners in Rust so
// refreshes carry real failed-unit data.
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
  static void snapshotCallback(void* ctx, const char* json);
  void applySnapshot(const QString& json);

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
