#pragma once

#include <QObject>
#include <QString>

// Google Calendar cache. Rust fetches the configured calendars on a worker
// thread and delivers the full JSON payload; this QObject parses it on the Qt
// thread. Each property owns its change signal because the QML consumer reacts
// to `error` and `events_json` independently, and `events_json` is the apply
// trigger (fired last, after status/generated_at/error are updated).
class QsNativeIcal : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString events_json READ eventsJson NOTIFY events_jsonChanged)
  Q_PROPERTY(QString generated_at READ generatedAt NOTIFY generated_atChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsNativeIcal(QObject* parent = nullptr);

  [[nodiscard]] auto eventsJson() const -> QString { return m_eventsJson; }
  [[nodiscard]] auto generatedAt() const -> QString { return m_generatedAt; }
  [[nodiscard]] auto status() const -> QString { return m_status; }
  [[nodiscard]] auto error() const -> QString { return m_error; }

  Q_INVOKABLE auto refresh(int days) -> bool;

signals:
  void events_jsonChanged();
  void generated_atChanged();
  void statusChanged();
  void errorChanged();

private:
  static void snapshotCallback(void* ctx, const char* json);
  void applySnapshot(const QString& json);

  QString m_eventsJson;
  QString m_generatedAt;
  QString m_status;
  QString m_error;
};
