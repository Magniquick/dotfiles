#pragma once
#include <QObject>

class QsGoIcal : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString events_json READ eventsJson NOTIFY eventsJsonChanged)
  Q_PROPERTY(QString generated_at READ generatedAt NOTIFY generatedAtChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsGoIcal(QObject* parent = nullptr);

  [[nodiscard]] auto eventsJson() const -> QString {
    return m_eventsJson;
  }
  [[nodiscard]] auto generatedAt() const -> QString {
    return m_generatedAt;
  }
  [[nodiscard]] auto status() const -> QString {
    return m_status;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }

  Q_INVOKABLE auto refresh(int days) -> bool;

signals:
  void eventsJsonChanged();
  void generatedAtChanged();
  void statusChanged();
  void errorChanged();

private:
  QString m_eventsJson;
  QString m_generatedAt;
  QString m_status;
  QString m_error;
};
