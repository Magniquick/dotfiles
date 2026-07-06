#include "QsNativeSystemdFailedProvider.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>

namespace {

// Builds a QVariantList of QVariantMaps with the load-bearing key order:
// unit, load, active, sub, description (all QString). Empty here in the stub.
auto parseFailedUnits(const QJsonArray& array) -> QVariantList {
  QVariantList list;
  list.reserve(array.size());
  for (const auto& value : array) {
    const QJsonObject unit = value.toObject();
    QVariantMap map;
    map.insert(QStringLiteral("unit"), unit.value(QStringLiteral("unit")).toString());
    map.insert(QStringLiteral("load"), unit.value(QStringLiteral("load")).toString());
    map.insert(QStringLiteral("active"), unit.value(QStringLiteral("active")).toString());
    map.insert(QStringLiteral("sub"), unit.value(QStringLiteral("sub")).toString());
    map.insert(QStringLiteral("description"), unit.value(QStringLiteral("description")).toString());
    list.append(map);
  }
  return list;
}

}  // namespace

QsNativeSystemdFailedProvider::QsNativeSystemdFailedProvider(QObject* parent)
    : QObject(parent), m_handle(QsNative_SystemdFailedProvider_New()) {}

QsNativeSystemdFailedProvider::~QsNativeSystemdFailedProvider() {
  QsNative_SystemdFailedProvider_Delete(m_handle);
}

void QsNativeSystemdFailedProvider::start() {
  // TODO(stage2): spawn the debounce worker + systemd D-Bus listeners once.
  refresh();
}

auto QsNativeSystemdFailedProvider::refresh() -> bool {
  m_refreshing = true;
  emit changed();
  QsNative_SystemdFailedProvider_Refresh(m_handle, this,
                                         &QsNativeSystemdFailedProvider::snapshotCallback);
  return true;
}

void QsNativeSystemdFailedProvider::scheduleRefresh() {
  // TODO(stage2): tick the debounce channel. No-op in the stub.
}

void QsNativeSystemdFailedProvider::snapshotCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativeSystemdFailedProvider*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applySnapshot(payload); });
}

void QsNativeSystemdFailedProvider::applySnapshot(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    m_refreshing = false;
    emit changed();
    return;
  }
  const QJsonObject o = doc.object();

  m_systemFailedCount = o.value(QStringLiteral("system_failed_count")).toInt();
  m_userFailedCount = o.value(QStringLiteral("user_failed_count")).toInt();
  m_failedCount = o.value(QStringLiteral("failed_count")).toInt();
  m_systemFailedUnits = parseFailedUnits(o.value(QStringLiteral("system_failed_units")).toArray());
  m_userFailedUnits = parseFailedUnits(o.value(QStringLiteral("user_failed_units")).toArray());
  m_lastChecked = o.value(QStringLiteral("last_checked")).toString();
  m_error = o.value(QStringLiteral("error")).toString();
  m_refreshing = false;

  emit changed();
}
