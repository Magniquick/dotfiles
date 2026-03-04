#include "QsGoAiModels.h"
#include "qsgo_go_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoAiModels::QsGoAiModels(QObject* parent) : QObject(parent) {}

void QsGoAiModels::setOpenaiApiKey(const QString& v)
{ if (v != m_openaiApiKey) { m_openaiApiKey = v; emit openaiApiKeyChanged(); } }

void QsGoAiModels::setGeminiApiKey(const QString& v)
{ if (v != m_geminiApiKey) { m_geminiApiKey = v; emit geminiApiKeyChanged(); } }

void QsGoAiModels::setOpenaiBaseUrl(const QString& v)
{ if (v != m_openaiBaseUrl) { m_openaiBaseUrl = v; emit openaiBaseUrlChanged(); } }

bool QsGoAiModels::refresh()
{
  if (m_busy) return false;

  m_busy = true; emit busyChanged();
  m_status = QStringLiteral("Loading..."); emit statusChanged();
  m_error = QString(); emit errorChanged();

  const QByteArray ok  = m_openaiApiKey.toUtf8();
  const QByteArray gk  = m_geminiApiKey.toUtf8();
  const QByteArray url = m_openaiBaseUrl.toUtf8();

  QThreadPool::globalInstance()->start([this, ok, gk, url]() {
    char* raw = QsGo_AiModels_Refresh(ok.constData(), gk.constData(), url.constData());
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

      // Store the full models array as JSON string for QML consumption.
      const QJsonValue modelsVal = obj.value(QLatin1String("models"));
      const QByteArray modelsJson = QJsonDocument(modelsVal.toArray()).toJson(QJsonDocument::Compact);
      const QString modelsStr = QString::fromUtf8(modelsJson);
      if (modelsStr != m_modelsJson) { m_modelsJson = modelsStr; emit modelsJsonChanged(); }

      const QString status = obj.value(QLatin1String("status")).toString();
      if (status != m_status) { m_status = status; emit statusChanged(); }

      const QString err = obj.value(QLatin1String("error")).toString();
      if (err != m_error) { m_error = err; emit errorChanged(); }
    }, Qt::QueuedConnection);
  });

  return true;
}
