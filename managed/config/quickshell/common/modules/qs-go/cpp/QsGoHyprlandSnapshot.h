#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QsGoHyprlandSnapshot : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantMap activeWorkspace READ activeWorkspace NOTIFY activeWorkspaceChanged)
  Q_PROPERTY(QVariantList clients READ clients NOTIFY clientsChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(bool running READ running NOTIFY runningChanged)
  Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
  explicit QsGoHyprlandSnapshot(QObject* parent = nullptr);
  ~QsGoHyprlandSnapshot() override;

  QVariantMap activeWorkspace() const { return m_activeWorkspace; }
  QVariantList clients() const { return m_clients; }
  QString error() const { return m_error; }
  bool running() const { return m_monitorId >= 0; }
  int revision() const { return m_revision; }

  Q_INVOKABLE void start();
  Q_INVOKABLE void stop();
  Q_INVOKABLE bool refresh();

signals:
  void activeWorkspaceChanged();
  void clientsChanged();
  void errorChanged();
  void runningChanged();
  void revisionChanged();

private:
  static void monitorCallback(void* ctx);
  void applySnapshot(const QByteArray& json);
  void setError(const QString& error);

  QVariantMap m_activeWorkspace;
  QVariantList m_clients;
  QString m_error;
  int m_monitorId = -1;
  bool m_refreshInFlight = false;
  bool m_refreshPending = false;
  int m_revision = 0;
};
