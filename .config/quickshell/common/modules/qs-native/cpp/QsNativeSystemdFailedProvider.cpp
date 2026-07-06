#include "QsNativeSystemdFailedProvider.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QString>
#include <QVariantMap>

namespace {

// Deep-copies a borrowed FailedUnitC array into a QVariantList of QVariantMaps
// with the QML-facing keys: unit, load, active, sub, description (all QString).
auto unitsToVariantList(const FailedUnitC* units, size_t len) -> QVariantList {
  QVariantList out;
  for (size_t i = 0; i < len; ++i) {
    QVariantMap map;
    map.insert(QStringLiteral("unit"), QString::fromUtf8(units[i].unit));
    map.insert(QStringLiteral("load"), QString::fromUtf8(units[i].load));
    map.insert(QStringLiteral("active"), QString::fromUtf8(units[i].active));
    map.insert(QStringLiteral("sub"), QString::fromUtf8(units[i].sub));
    map.insert(QStringLiteral("description"), QString::fromUtf8(units[i].description));
    out.append(map);
  }
  return out;
}

} // namespace

QsNativeSystemdFailedProvider::QsNativeSystemdFailedProvider(QObject* parent)
    : QObject(parent), m_handle(QsNative_SystemdFailedProvider_New()) {}

QsNativeSystemdFailedProvider::~QsNativeSystemdFailedProvider() {
  QsNative_SystemdFailedProvider_Delete(m_handle);
}

void QsNativeSystemdFailedProvider::start() {
  m_refreshing = true;
  emit changed();
  QsNative_SystemdFailedProvider_Start(m_handle, this,
                                       &QsNativeSystemdFailedProvider::snapshotCallback);
}

auto QsNativeSystemdFailedProvider::refresh() -> bool {
  m_refreshing = true;
  emit changed();
  return QsNative_SystemdFailedProvider_Refresh(m_handle, this,
                                                &QsNativeSystemdFailedProvider::snapshotCallback);
}

void QsNativeSystemdFailedProvider::scheduleRefresh() {
  QsNative_SystemdFailedProvider_ScheduleRefresh(m_handle);
}

void QsNativeSystemdFailedProvider::snapshotCallback(void* ctx, const SystemdFailedSnapshotC* snap) {
  auto* self = static_cast<QsNativeSystemdFailedProvider*>(ctx);
  if (snap == nullptr) {
    return;
  }

  // Deep-copy synchronously: the pointers are only valid for this call.
  const int systemCount = snap->system_failed_count;
  const int userCount = snap->user_failed_count;
  const int failedCount = snap->failed_count;
  const QVariantList systemUnits = unitsToVariantList(snap->system_units, snap->system_units_len);
  const QVariantList userUnits = unitsToVariantList(snap->user_units, snap->user_units_len);
  const QString lastChecked = QString::fromUtf8(snap->last_checked);
  const QString error = QString::fromUtf8(snap->error);

  qsn::postToObject(self, [self, systemCount, userCount, failedCount, systemUnits, userUnits,
                           lastChecked, error]() {
    self->applySnapshot(systemCount, userCount, failedCount, systemUnits, userUnits, lastChecked,
                        error);
  });
}

void QsNativeSystemdFailedProvider::applySnapshot(int systemFailedCount, int userFailedCount,
                                                  int failedCount,
                                                  const QVariantList& systemFailedUnits,
                                                  const QVariantList& userFailedUnits,
                                                  const QString& lastChecked, const QString& error) {
  m_systemFailedCount = systemFailedCount;
  m_userFailedCount = userFailedCount;
  m_failedCount = failedCount;
  m_systemFailedUnits = systemFailedUnits;
  m_userFailedUnits = userFailedUnits;
  m_lastChecked = lastChecked;
  m_error = error;
  m_refreshing = false;
  emit changed();
}
