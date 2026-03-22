#include "QsGoAiModels.h"
#include "qsgo_go_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoAiModels::QsGoAiModels(QObject* parent) : QObject(parent) {}

void QsGoAiModels::setProviderConfig(const QVariantMap& v)
{
  if (v != m_providerConfig) {
    m_providerConfig = v;
    emit providerConfigChanged();
  }
}

bool QsGoAiModels::refresh()
{
  if (m_busy) return false;

  m_busy = true; emit busyChanged();
  m_status = QStringLiteral("Loading..."); emit statusChanged();
  m_error = QString(); emit errorChanged();

  const QByteArray configJson = QJsonDocument::fromVariant(m_providerConfig).toJson(QJsonDocument::Compact);

  QThreadPool::globalInstance()->start([this, configJson]() {
    char* raw = QsGo_AiModels_Refresh(configJson.constData());
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      m_busy = false; emit busyChanged();

      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) {
        m_status = QStringLiteral("Error"); emit statusChanged();
        m_error  = QStringLiteral("Invalid response"); emit errorChanged();
        return;
      }
      const QJsonObject obj = doc.object();

      const QVariantList providers = obj.value(QLatin1String("providers")).toArray().toVariantList();
      if (providers != m_providers) { m_providers = providers; emit providersChanged(); }

      const QString status = obj.value(QLatin1String("status")).toString();
      if (status != m_status) { m_status = status; emit statusChanged(); }

      const QString err = obj.value(QLatin1String("error")).toString();
      if (err != m_error) { m_error = err; emit errorChanged(); }
    }, Qt::QueuedConnection);
  });

  return true;
}
