#pragma once
#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QsGoAiModels : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantList providers           READ providers       NOTIFY providersChanged)
  Q_PROPERTY(bool         busy                READ busy            NOTIFY busyChanged)
  Q_PROPERTY(QString      status              READ status          NOTIFY statusChanged)
  Q_PROPERTY(QString      error               READ error           NOTIFY errorChanged)
  Q_PROPERTY(QVariantMap  provider_config     READ providerConfig  WRITE setProviderConfig NOTIFY providerConfigChanged)

public:
  explicit QsGoAiModels(QObject* parent = nullptr);

  QVariantList providers() const { return m_providers; }
  bool         busy() const { return m_busy; }
  QString      status() const { return m_status; }
  QString      error() const { return m_error; }
  QVariantMap  providerConfig() const { return m_providerConfig; }

  void setProviderConfig(const QVariantMap& v);

  Q_INVOKABLE bool refresh();

signals:
  void providersChanged();
  void busyChanged();
  void statusChanged();
  void errorChanged();
  void providerConfigChanged();

private:
  QVariantList m_providers;
  bool         m_busy = false;
  QString      m_status;
  QString      m_error;
  QVariantMap  m_providerConfig;
};
