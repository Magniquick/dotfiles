#pragma once

#include <QDBusObjectPath>
#include <QObject>
#include <QString>
#include <QTimer>
#include <QVariantList>

class QsGoSystemdFailed : public QObject {
  Q_OBJECT

  Q_PROPERTY(int system_failed_count READ systemFailedCount NOTIFY systemFailedCountChanged)
  Q_PROPERTY(int user_failed_count READ userFailedCount NOTIFY userFailedCountChanged)
  Q_PROPERTY(int failed_count READ failedCount NOTIFY failedCountChanged)
  Q_PROPERTY(
      QVariantList system_failed_units READ systemFailedUnits NOTIFY systemFailedUnitsChanged)
  Q_PROPERTY(QVariantList user_failed_units READ userFailedUnits NOTIFY userFailedUnitsChanged)
  Q_PROPERTY(QString last_checked READ lastChecked NOTIFY lastCheckedChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(bool refreshing READ refreshing NOTIFY refreshingChanged)

public:
  explicit QsGoSystemdFailed(QObject* parent = nullptr);

  [[nodiscard]] auto systemFailedCount() const -> int {
    return m_systemFailedCount;
  }
  [[nodiscard]] auto userFailedCount() const -> int {
    return m_userFailedCount;
  }
  [[nodiscard]] auto failedCount() const -> int {
    return m_failedCount;
  }
  [[nodiscard]] auto systemFailedUnits() const -> QVariantList {
    return m_systemFailedUnits;
  }
  [[nodiscard]] auto userFailedUnits() const -> QVariantList {
    return m_userFailedUnits;
  }
  [[nodiscard]] auto lastChecked() const -> QString {
    return m_lastChecked;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }
  [[nodiscard]] auto refreshing() const -> bool {
    return m_refreshing;
  }

  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE void start();

signals:
  void systemFailedCountChanged();
  void userFailedCountChanged();
  void failedCountChanged();
  void systemFailedUnitsChanged();
  void userFailedUnitsChanged();
  void lastCheckedChanged();
  void errorChanged();
  void refreshingChanged();

private slots:
  void onSystemdChanged();
  void onSystemdJobRemoved(uint id, const QDBusObjectPath& job, const QString& unit,
                           const QString& result);
  void onSystemdUnitChanged(const QString& unit, const QDBusObjectPath& path);

  void connectSystemdSignals();
  void scheduleRefresh();
  void applyJson(const QByteArray& json);
  [[nodiscard]] static auto parseUnits(const QJsonValue& value) -> QVariantList;
  void setRefreshing(bool refreshing);

private:
  int m_systemFailedCount = 0;
  int m_userFailedCount = 0;
  int m_failedCount = 0;
  QVariantList m_systemFailedUnits;
  QVariantList m_userFailedUnits;
  QString m_lastChecked;
  QString m_error;
  bool m_refreshing = false;
  bool m_started = false;
  QTimer m_debounceTimer;
};
