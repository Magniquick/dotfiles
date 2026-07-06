#include "QsNativeBluetooth.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QJsonDocument>
#include <QJsonObject>

QsNativeBluetooth::QsNativeBluetooth(QObject* parent)
    : QObject(parent), m_handle(QsNative_Bluetooth_New()) {}

QsNativeBluetooth::~QsNativeBluetooth() {
  QsNative_Bluetooth_Delete(m_handle);
}

// ── Property setters (compare-and-emit qproperty semantics) ──

void QsNativeBluetooth::setLastStartDiscoverySender(const QString& v) {
  if (v != m_lastStartDiscoverySender) {
    m_lastStartDiscoverySender = v;
    emit last_start_discovery_senderChanged();
  }
}

void QsNativeBluetooth::setLastStartDiscoveryPid(int v) {
  if (v != m_lastStartDiscoveryPid) {
    m_lastStartDiscoveryPid = v;
    emit last_start_discovery_pidChanged();
  }
}

void QsNativeBluetooth::setLastStartDiscoveryProcess(const QString& v) {
  if (v != m_lastStartDiscoveryProcess) {
    m_lastStartDiscoveryProcess = v;
    emit last_start_discovery_processChanged();
  }
}

void QsNativeBluetooth::setLastScanHolders(const QString& v) {
  if (v != m_lastScanHolders) {
    m_lastScanHolders = v;
    emit last_scan_holdersChanged();
  }
}

void QsNativeBluetooth::setLibrepodsTooltip(const QString& v) {
  if (v != m_librepodsTooltip) {
    m_librepodsTooltip = v;
    emit librepods_tooltipChanged();
  }
}

void QsNativeBluetooth::setError(const QString& v) {
  if (v != m_error) {
    m_error = v;
    emit errorChanged();
  }
}

void QsNativeBluetooth::setMonitoring(bool v) {
  if (v != m_monitoring) {
    m_monitoring = v;
    emit monitoringChanged();
  }
}

// ── Invokables ────────────────────────────────────────────────────────────────

auto QsNativeBluetooth::startDiscoveryMonitor() -> bool {
  if (m_monitoring) {
    return true;
  }
  setMonitoring(true);
  QsNative_Bluetooth_StartDiscoveryMonitor(m_handle, this, &QsNativeBluetooth::snapshotCallback);
  return true;
}

void QsNativeBluetooth::stopDiscoveryMonitor() {
  QsNative_Bluetooth_StopDiscoveryMonitor(m_handle);
}

auto QsNativeBluetooth::probeScanHolders() -> bool {
  setLastScanHolders(qsn::takeString(QsNative_Bluetooth_ScanHolders()));
  return true;
}

auto QsNativeBluetooth::probeLibrepodsTooltip() -> bool {
  QsNative_Bluetooth_ProbeLibrepodsTooltip(this, &QsNativeBluetooth::snapshotCallback);
  return true;
}

// ── Worker callback (worker thread → queued to the Qt thread) ─────────────────

void QsNativeBluetooth::snapshotCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativeBluetooth*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applySnapshot(payload); });
}

void QsNativeBluetooth::applySnapshot(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    return;
  }
  const QJsonObject o = doc.object();

  if (o.contains(QStringLiteral("last_start_discovery_sender"))) {
    setLastStartDiscoverySender(o.value(QStringLiteral("last_start_discovery_sender")).toString());
  }
  if (o.contains(QStringLiteral("last_start_discovery_pid"))) {
    setLastStartDiscoveryPid(o.value(QStringLiteral("last_start_discovery_pid")).toInt());
  }
  if (o.contains(QStringLiteral("last_start_discovery_process"))) {
    setLastStartDiscoveryProcess(
        o.value(QStringLiteral("last_start_discovery_process")).toString());
  }
  if (o.contains(QStringLiteral("last_scan_holders"))) {
    setLastScanHolders(o.value(QStringLiteral("last_scan_holders")).toString());
  }
  if (o.contains(QStringLiteral("librepods_tooltip"))) {
    setLibrepodsTooltip(o.value(QStringLiteral("librepods_tooltip")).toString());
  }
  if (o.contains(QStringLiteral("error"))) {
    setError(o.value(QStringLiteral("error")).toString());
  }
  if (o.contains(QStringLiteral("monitoring"))) {
    setMonitoring(o.value(QStringLiteral("monitoring")).toBool());
  }
}
