#include "QsGoSystemdFailed.h"
#include "qsgo_go_api.h"

#include <QDBusConnection>
#include <QDBusObjectPath>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>
#include <QVariantMap>

namespace {

const QString SystemdService = QStringLiteral("org.freedesktop.systemd1");
const QString SystemdPath = QStringLiteral("/org/freedesktop/systemd1");
const QString SystemdManager = QStringLiteral("org.freedesktop.systemd1.Manager");

void connectManagerSignal(QDBusConnection bus, QObject* receiver, const QString& signal,
                          const char* slot) {
  bus.connect(SystemdService, SystemdPath, SystemdManager, signal, receiver, slot);
}

} // namespace

QsGoSystemdFailed::QsGoSystemdFailed(QObject* parent) : QObject(parent) {
  m_debounceTimer.setSingleShot(true);
  m_debounceTimer.setInterval(250);
  connect(&m_debounceTimer, &QTimer::timeout, this, &QsGoSystemdFailed::refresh);
}

void QsGoSystemdFailed::start() {
  if (!m_started) {
    m_started = true;
    connectSystemdSignals();
  }
  refresh();
}

bool QsGoSystemdFailed::refresh() {
  setRefreshing(true);
  QThreadPool::globalInstance()->start([this]() {
    char* raw = QsGo_SystemdFailed_Refresh();
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(
        this,
        [this, json]() {
          applyJson(json);
          setRefreshing(false);
        },
        Qt::QueuedConnection);
  });
  return true;
}

void QsGoSystemdFailed::connectSystemdSignals() {
  for (const QDBusConnection& bus : {QDBusConnection::systemBus(), QDBusConnection::sessionBus()}) {
    connectManagerSignal(bus, this, QStringLiteral("UnitFilesChanged"), SLOT(onSystemdChanged()));
    connectManagerSignal(bus, this, QStringLiteral("Reloading"), SLOT(onSystemdChanged()));
    connectManagerSignal(bus, this, QStringLiteral("JobRemoved"),
                         SLOT(onSystemdJobRemoved(uint, QDBusObjectPath, QString, QString)));
    connectManagerSignal(bus, this, QStringLiteral("UnitNew"),
                         SLOT(onSystemdUnitChanged(QString, QDBusObjectPath)));
    connectManagerSignal(bus, this, QStringLiteral("UnitRemoved"),
                         SLOT(onSystemdUnitChanged(QString, QDBusObjectPath)));
  }
}

void QsGoSystemdFailed::scheduleRefresh() {
  m_debounceTimer.start();
}

void QsGoSystemdFailed::onSystemdChanged() {
  scheduleRefresh();
}

void QsGoSystemdFailed::onSystemdJobRemoved(uint, const QDBusObjectPath&, const QString&,
                                            const QString&) {
  scheduleRefresh();
}

void QsGoSystemdFailed::onSystemdUnitChanged(const QString&, const QDBusObjectPath&) {
  scheduleRefresh();
}

void QsGoSystemdFailed::applyJson(const QByteArray& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if (!doc.isObject()) {
    const QString err = QStringLiteral("Invalid systemd provider response");
    if (err != m_error) {
      m_error = err;
      emit errorChanged();
    }
    return;
  }

  const QJsonObject obj = doc.object();

#define SET_INT(member, signal, key)                                                               \
  {                                                                                                \
    const int v = obj.value(QLatin1String(key)).toInt();                                           \
    if (v != member) {                                                                             \
      member = v;                                                                                  \
      emit signal();                                                                               \
    }                                                                                              \
  }

  SET_INT(m_systemFailedCount, systemFailedCountChanged, "system_failed_count")
  SET_INT(m_userFailedCount, userFailedCountChanged, "user_failed_count")
  SET_INT(m_failedCount, failedCountChanged, "failed_count")

#undef SET_INT

  const QVariantList systemUnits = parseUnits(obj.value(QLatin1String("system_failed_units")));
  if (systemUnits != m_systemFailedUnits) {
    m_systemFailedUnits = systemUnits;
    emit systemFailedUnitsChanged();
  }

  const QVariantList userUnits = parseUnits(obj.value(QLatin1String("user_failed_units")));
  if (userUnits != m_userFailedUnits) {
    m_userFailedUnits = userUnits;
    emit userFailedUnitsChanged();
  }

  const QString lastChecked = obj.value(QLatin1String("last_checked")).toString();
  if (lastChecked != m_lastChecked) {
    m_lastChecked = lastChecked;
    emit lastCheckedChanged();
  }

  const QString error = obj.value(QLatin1String("error")).toString();
  if (error != m_error) {
    m_error = error;
    emit errorChanged();
  }
}

QVariantList QsGoSystemdFailed::parseUnits(const QJsonValue& value) const {
  QVariantList units;
  const QJsonArray arr = value.toArray();
  units.reserve(arr.size());
  for (const QJsonValue& v : arr) {
    if (!v.isObject())
      continue;
    const QJsonObject obj = v.toObject();
    QVariantMap unit;
    unit.insert(QStringLiteral("unit"), obj.value(QLatin1String("unit")).toString());
    unit.insert(QStringLiteral("load"), obj.value(QLatin1String("load")).toString());
    unit.insert(QStringLiteral("active"), obj.value(QLatin1String("active")).toString());
    unit.insert(QStringLiteral("sub"), obj.value(QLatin1String("sub")).toString());
    unit.insert(QStringLiteral("description"), obj.value(QLatin1String("description")).toString());
    units.append(unit);
  }
  return units;
}

void QsGoSystemdFailed::setRefreshing(bool refreshing) {
  if (refreshing == m_refreshing)
    return;
  m_refreshing = refreshing;
  emit refreshingChanged();
}
