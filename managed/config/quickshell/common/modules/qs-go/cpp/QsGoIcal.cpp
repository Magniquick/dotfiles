#include "QsGoIcal.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoIcal::QsGoIcal(QObject* parent) : QObject(parent) {}

bool QsGoIcal::refreshFromEnv(const QString& envFile, int days)
{
  const QByteArray ef = envFile.toUtf8();
  QThreadPool::globalInstance()->start([this, ef, days]() {
    char* raw = QsGo_Ical_Refresh(ef.constData(), days);
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) return;
      const QJsonObject obj = doc.object();

#define SETSTR(member, sig, key) \
      { auto v = obj.value(QLatin1String(key)).toString(); if (v != member) { member = v; emit sig(); } }

      SETSTR(m_eventsJson,  eventsJsonChanged,  "events_json")
      SETSTR(m_generatedAt, generatedAtChanged, "generated_at")
      SETSTR(m_status,      statusChanged,      "status")
      SETSTR(m_error,       errorChanged,       "error")

#undef SETSTR
    }, Qt::QueuedConnection);
  });
  return true;
}
