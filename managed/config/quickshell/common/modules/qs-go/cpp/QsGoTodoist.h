#pragma once
#include <QObject>

class QsGoTodoist : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString data         READ data        NOTIFY dataChanged)
  Q_PROPERTY(bool    loading      READ loading     NOTIFY loadingChanged)
  Q_PROPERTY(QString error        READ error       NOTIFY errorChanged)
  Q_PROPERTY(QString last_updated READ lastUpdated NOTIFY lastUpdatedChanged)
  Q_PROPERTY(QString env_file     READ envFile     WRITE setEnvFile NOTIFY envFileChanged)

public:
  explicit QsGoTodoist(QObject* parent = nullptr);

  QString data()        const { return m_data; }
  bool    loading()     const { return m_loading; }
  QString error()       const { return m_error; }
  QString lastUpdated() const { return m_lastUpdated; }
  QString envFile()     const { return m_envFile; }

  void setEnvFile(const QString& v);

  Q_INVOKABLE bool refresh();
  Q_INVOKABLE bool action(const QString& verb, const QString& argsJson);

signals:
  void dataChanged();
  void loadingChanged();
  void errorChanged();
  void lastUpdatedChanged();
  void envFileChanged();

private:
  QString m_data;
  bool    m_loading    = false;
  QString m_error;
  QString m_lastUpdated;
  QString m_envFile;
};
