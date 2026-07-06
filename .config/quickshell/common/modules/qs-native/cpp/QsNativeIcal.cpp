#include "QsNativeIcal.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QJsonDocument>
#include <QJsonObject>

QsNativeIcal::QsNativeIcal(QObject* parent) : QObject(parent) {}

auto QsNativeIcal::refresh(int days) -> bool {
  QsNative_Ical_Refresh(this, &QsNativeIcal::snapshotCallback, days);
  return true;
}

void QsNativeIcal::snapshotCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativeIcal*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applySnapshot(payload); });
}

void QsNativeIcal::applySnapshot(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    if (m_error != QStringLiteral("Invalid response")) {
      m_error = QStringLiteral("Invalid response");
      emit errorChanged();
    }
    return;
  }
  const QJsonObject o = doc.object();

  const QString generatedAt = o.value(QStringLiteral("generatedAt")).toString();
  if (generatedAt != m_generatedAt) {
    m_generatedAt = generatedAt;
    emit generated_atChanged();
  }

  const QString status = o.value(QStringLiteral("status")).toString();
  if (status != m_status) {
    m_status = status;
    emit statusChanged();
  }

  const QString error = o.value(QStringLiteral("error")).toString();
  if (error != m_error) {
    m_error = error;
    emit errorChanged();
  }

  // Fired last so QML's onEvents_jsonChanged applies after the other fields.
  if (json != m_eventsJson) {
    m_eventsJson = json;
    emit events_jsonChanged();
  }
}
