#include "QsNativeNetStats.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

QsNativeNetStats::QsNativeNetStats(QObject* parent)
    : QObject(parent), m_handle(QsNative_NetStats_New()) {}

QsNativeNetStats::~QsNativeNetStats() {
  QsNative_NetStats_Delete(m_handle);
}

void QsNativeNetStats::setDevice(const QString& device) {
  if (m_device == device) {
    return;
  }
  m_device = device;
  emit deviceChanged();
}

auto QsNativeNetStats::refresh() -> bool {
  const QVariantMap o = qsn::takeObject(QsNative_NetStats_Refresh(m_device.toUtf8().constData()));
  const bool ok = o.value(QStringLiteral("ok")).toBool();
  setError(o.value(QStringLiteral("error")).toString());
  if (ok) {
    const double rx = o.value(QStringLiteral("rx_bytes")).toDouble();
    const double tx = o.value(QStringLiteral("tx_bytes")).toDouble();
    setRxBytes(rx);
    setTxBytes(tx);
    emit sampleReady(rx, tx);
  }
  return ok;
}

void QsNativeNetStats::updateTrafficRates(double rx_bytes, double tx_bytes, double now_ms) {
  applyTrafficSnapshot(
      qsn::takeObject(QsNative_NetStats_UpdateTrafficRates(m_handle, rx_bytes, tx_bytes, now_ms)));
}

void QsNativeNetStats::resetTraffic() {
  applyTrafficSnapshot(qsn::takeObject(QsNative_NetStats_ResetTraffic(m_handle)));
}

auto QsNativeNetStats::setSourceEntries(const QString& entries_json) -> bool {
  const QVariantMap o = qsn::takeObject(
      QsNative_NetStats_SetSourceEntries(m_handle, entries_json.toUtf8().constData()));
  const bool ok = o.value(QStringLiteral("ok")).toBool();
  applySourceSnapshot(o);
  if (!ok) {
    setError(o.value(QStringLiteral("error")).toString());
  }
  return ok;
}

auto QsNativeNetStats::beginSourceSwitch(const QString& name) -> bool {
  const QVariantMap o =
      qsn::takeObject(QsNative_NetStats_BeginSourceSwitch(m_handle, name.toUtf8().constData()));
  applySourceSnapshot(o);
  return o.value(QStringLiteral("ok")).toBool();
}

void QsNativeNetStats::failSourceSwitch(const QString& message) {
  applySourceSnapshot(
      qsn::takeObject(QsNative_NetStats_FailSourceSwitch(m_handle, message.toUtf8().constData())));
}

void QsNativeNetStats::clearSourceSwitch() {
  applySourceSnapshot(qsn::takeObject(QsNative_NetStats_ClearSourceSwitch(m_handle)));
}

auto QsNativeNetStats::parseIpAddressJson(const QString& text) const -> QString {
  return qsn::takeString(QsNative_NetStats_ParseIpAddressJson(text.toUtf8().constData()));
}

auto QsNativeNetStats::parseGatewayJson(const QString& text) const -> QString {
  return qsn::takeString(QsNative_NetStats_ParseGatewayJson(text.toUtf8().constData()));
}

auto QsNativeNetStats::normalizeEthernetLabel(const QString& text) const -> QString {
  return qsn::takeString(QsNative_NetStats_NormalizeEthernetLabel(text.toUtf8().constData()));
}

auto QsNativeNetStats::ethernetMetadataJson(const QString& device_name) const -> QString {
  return qsn::takeString(QsNative_NetStats_EthernetMetadataJson(device_name.toUtf8().constData()));
}

void QsNativeNetStats::applyTrafficSnapshot(const QVariantMap& o) {
  if (o.isEmpty()) {
    return;
  }
  setRxBytesPerSec(o.value(QStringLiteral("rxBytesPerSec")).toDouble());
  setTxBytesPerSec(o.value(QStringLiteral("txBytesPerSec")).toDouble());
  setTrafficScaleMax(o.value(QStringLiteral("trafficScaleMax")).toDouble());
  setRxHistoryJson(o.value(QStringLiteral("rxHistoryJson")).toString());
  setTxHistoryJson(o.value(QStringLiteral("txHistoryJson")).toString());
}

void QsNativeNetStats::applySourceSnapshot(const QVariantMap& o) {
  if (o.isEmpty()) {
    return;
  }
  setSourceEntriesJson(o.value(QStringLiteral("sourceEntriesJson")).toString());
  setSourceSwitching(o.value(QStringLiteral("sourceSwitching")).toBool());
  setSourceSwitchingName(o.value(QStringLiteral("sourceSwitchingName")).toString());
  setSourceError(o.value(QStringLiteral("sourceError")).toString());
}

void QsNativeNetStats::setRxBytes(double v) {
  if (m_rxBytes == v) {
    return;
  }
  m_rxBytes = v;
  emit rx_bytesChanged();
}

void QsNativeNetStats::setTxBytes(double v) {
  if (m_txBytes == v) {
    return;
  }
  m_txBytes = v;
  emit tx_bytesChanged();
}

void QsNativeNetStats::setRxBytesPerSec(double v) {
  if (m_rxBytesPerSec == v) {
    return;
  }
  m_rxBytesPerSec = v;
  emit rxBytesPerSecChanged();
}

void QsNativeNetStats::setTxBytesPerSec(double v) {
  if (m_txBytesPerSec == v) {
    return;
  }
  m_txBytesPerSec = v;
  emit txBytesPerSecChanged();
}

void QsNativeNetStats::setRxHistoryJson(const QString& v) {
  if (m_rxHistoryJson == v) {
    return;
  }
  m_rxHistoryJson = v;
  emit rxHistoryJsonChanged();
}

void QsNativeNetStats::setTxHistoryJson(const QString& v) {
  if (m_txHistoryJson == v) {
    return;
  }
  m_txHistoryJson = v;
  emit txHistoryJsonChanged();
}

void QsNativeNetStats::setTrafficScaleMax(double v) {
  if (m_trafficScaleMax == v) {
    return;
  }
  m_trafficScaleMax = v;
  emit trafficScaleMaxChanged();
}

void QsNativeNetStats::setSourceEntriesJson(const QString& v) {
  if (m_sourceEntriesJson == v) {
    return;
  }
  m_sourceEntriesJson = v;
  emit sourceEntriesJsonChanged();
}

void QsNativeNetStats::setSourceSwitching(bool v) {
  if (m_sourceSwitching == v) {
    return;
  }
  m_sourceSwitching = v;
  emit sourceSwitchingChanged();
}

void QsNativeNetStats::setSourceSwitchingName(const QString& v) {
  if (m_sourceSwitchingName == v) {
    return;
  }
  m_sourceSwitchingName = v;
  emit sourceSwitchingNameChanged();
}

void QsNativeNetStats::setSourceError(const QString& v) {
  if (m_sourceError == v) {
    return;
  }
  m_sourceError = v;
  emit sourceErrorChanged();
}

void QsNativeNetStats::setError(const QString& v) {
  if (m_error == v) {
    return;
  }
  m_error = v;
  emit errorChanged();
}
