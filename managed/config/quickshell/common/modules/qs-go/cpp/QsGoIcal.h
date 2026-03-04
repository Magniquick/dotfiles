#pragma once
#include <QObject>

class QsGoIcal : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString events_json  READ eventsJson  NOTIFY eventsJsonChanged)
  Q_PROPERTY(QString generated_at READ generatedAt NOTIFY generatedAtChanged)
  Q_PROPERTY(QString status       READ status      NOTIFY statusChanged)
  Q_PROPERTY(QString error        READ error       NOTIFY errorChanged)

public:
  explicit QsGoIcal(QObject* parent = nullptr);

  QString eventsJson()  const { return m_eventsJson; }
  QString generatedAt() const { return m_generatedAt; }
  QString status()      const { return m_status; }
  QString error()       const { return m_error; }

  Q_INVOKABLE bool refreshFromEnv(const QString& envFile, int days);

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
