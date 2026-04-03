#include "QsGoHyprlandSnapshot.h"
#include "qsgo_go_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoHyprlandSnapshot::QsGoHyprlandSnapshot(QObject* parent) : QObject(parent) {}

QsGoHyprlandSnapshot::~QsGoHyprlandSnapshot()
{
  stop();
}

void QsGoHyprlandSnapshot::start()
{
  if (m_monitorId >= 0) {
    refresh();
    return;
  }

  m_monitorId = QsGo_Hyprland_Monitor(&QsGoHyprlandSnapshot::monitorCallback, this);
  emit runningChanged();
  refresh();
}

void QsGoHyprlandSnapshot::stop()
{
  if (m_monitorId < 0)
    return;

  QsGo_Hyprland_StopMonitor(m_monitorId);
  m_monitorId = -1;
  m_refreshPending = false;
  emit runningChanged();
}

bool QsGoHyprlandSnapshot::refresh()
{
  if (m_refreshInFlight) {
    m_refreshPending = true;
    return true;
  }

  m_refreshInFlight = true;
  QThreadPool::globalInstance()->start([this]() {
    char* raw = QsGo_Hyprland_Refresh();
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      m_refreshInFlight = false;
      applySnapshot(json);

      if (m_refreshPending) {
        m_refreshPending = false;
        refresh();
      }
    }, Qt::QueuedConnection);
  });

  return true;
}

void QsGoHyprlandSnapshot::monitorCallback(void* ctx)
{
  auto* self = static_cast<QsGoHyprlandSnapshot*>(ctx);
  QMetaObject::invokeMethod(self, [self]() {
    self->refresh();
  }, Qt::QueuedConnection);
}

void QsGoHyprlandSnapshot::applySnapshot(const QByteArray& json)
{
  const QJsonDocument document = QJsonDocument::fromJson(json);
  if (!document.isObject()) {
    setError(QStringLiteral("Invalid Hyprland snapshot"));
    return;
  }

  const QJsonObject object = document.object();
  const QString nextError = object.value(QLatin1String("error")).toString();
  if (!nextError.isEmpty()) {
    setError(nextError);
    return;
  }

  const QVariantMap nextActiveWorkspace = object.value(QLatin1String("activeWorkspace")).toObject().toVariantMap();
  const QVariantList nextClients = object.value(QLatin1String("clients")).toArray().toVariantList();

  if (nextActiveWorkspace != m_activeWorkspace) {
    m_activeWorkspace = nextActiveWorkspace;
    emit activeWorkspaceChanged();
  }
  if (nextClients != m_clients) {
    m_clients = nextClients;
    emit clientsChanged();
  }

  m_revision += 1;
  emit revisionChanged();
  setError(QString());
}

void QsGoHyprlandSnapshot::setError(const QString& error)
{
  if (error == m_error)
    return;
  m_error = error;
  emit errorChanged();
}
