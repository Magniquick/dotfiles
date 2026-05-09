#include "QsGoIcal.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoIcal::QsGoIcal(QObject* parent) : QObject(parent) {}

bool QsGoIcal::refresh(int days) {
  QThreadPool::globalInstance()->start([this, days]() {
    char* raw = QsGo_Ical_Refresh(days);
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(
        this,
        [this, json]() {
          const QJsonDocument doc = QJsonDocument::fromJson(json);
          if (!doc.isObject()) {
            const QString err = QStringLiteral("Invalid response");
            if (err != m_error) {
              m_error = err;
              emit errorChanged();
            }
            return;
          }

          const QString payloadJson = QString::fromUtf8(json);
          if (payloadJson != m_eventsJson) {
            m_eventsJson = payloadJson;
            emit eventsJsonChanged();
          }

          if (!m_error.isEmpty()) {
            m_error.clear();
            emit errorChanged();
          }
        },
        Qt::QueuedConnection);
  });
  return true;
}
