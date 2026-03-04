#include "QsGoTodoist.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoTodoist::QsGoTodoist(QObject* parent) : QObject(parent) {}

void QsGoTodoist::setEnvFile(const QString& v)
{ if (v != m_envFile) { m_envFile = v; emit envFileChanged(); } }

void QsGoTodoist::setCachePath(const QString& v)
{ if (v != m_cachePath) { m_cachePath = v; emit cachePathChanged(); } }

void QsGoTodoist::setPreferCache(bool v)
{ if (v != m_preferCache) { m_preferCache = v; emit preferCacheChanged(); } }

bool QsGoTodoist::refresh()
{
  if (m_loading) return false;
  m_loading = true; emit loadingChanged();
  m_error = QString(); emit errorChanged();

  const QByteArray ef = m_envFile.toUtf8();
  const QByteArray cp = m_cachePath.toUtf8();
  const int preferCache = m_preferCache ? 1 : 0;
  QThreadPool::globalInstance()->start([this, ef, cp, preferCache]() {
    char* raw = QsGo_Todoist_List(ef.constData(), cp.constData(), preferCache);
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      m_loading = false; emit loadingChanged();

      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) {
        m_error = QStringLiteral("Invalid response"); emit errorChanged();
        return;
      }
      const QJsonObject obj = doc.object();

      { auto v = obj.value(QLatin1String("error")).toString();
        if (v != m_error) { m_error = v; emit errorChanged(); } }
      { auto v = obj.value(QLatin1String("last_updated")).toString();
        if (v != m_lastUpdated) { m_lastUpdated = v; emit lastUpdatedChanged(); } }

      // Store whole JSON as data for QML consumption
      const QString dataStr = QString::fromUtf8(json);
      if (dataStr != m_data) { m_data = dataStr; emit dataChanged(); }
    }, Qt::QueuedConnection);
  });
  return true;
}

bool QsGoTodoist::action(const QString& verb, const QString& argsJson)
{
  const QByteArray ef   = m_envFile.toUtf8();
  const QByteArray vb   = verb.toUtf8();
  const QByteArray args = argsJson.toUtf8();
  QThreadPool::globalInstance()->start([this, ef, vb, args]() {
    char* raw = QsGo_Todoist_Action(ef.constData(), vb.constData(), args.constData());
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      // After any action, refresh to get updated state
      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (doc.isObject()) {
        const QString err = doc.object().value(QLatin1String("error")).toString();
        if (err != m_error) { m_error = err; emit errorChanged(); }
      }
      refresh();
    }, Qt::QueuedConnection);
  });
  return true;
}
