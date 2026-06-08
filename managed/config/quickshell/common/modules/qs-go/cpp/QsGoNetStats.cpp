#include "QsGoNetStats.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoNetStats::QsGoNetStats(QObject* parent) : QObject(parent) {}

void QsGoNetStats::setDevice(const QString& value) {
  const QString next = value.trimmed();
  if (m_device == next) {
    return;
  }
  m_device = next;
  emit deviceChanged();
}

auto QsGoNetStats::refresh() -> bool {
  const QString device = m_device.trimmed();
  if (device.isEmpty()) {
    if (m_error != QStringLiteral("interface is empty")) {
      m_error = QStringLiteral("interface is empty");
      emit errorChanged();
    }
    return false;
  }

  QThreadPool::globalInstance()->start([this, device]() -> void {
    const QByteArray deviceBytes = device.toUtf8();
    char* raw = QsGo_SysStats_NetDev(deviceBytes.constData());
    QByteArray const json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(
        this, [this, json]() -> void { applySnapshot(json); }, Qt::QueuedConnection);
  });
  return true;
}

void QsGoNetStats::applySnapshot(const QByteArray& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if (!doc.isObject()) {
    if (m_error != QStringLiteral("Invalid response")) {
      m_error = QStringLiteral("Invalid response");
      emit errorChanged();
    }
    return;
  }

  const QJsonObject obj = doc.object();
  const QString nextError = obj.value(QLatin1String("error")).toString();
  if (m_error != nextError) {
    m_error = nextError;
    emit errorChanged();
  }
  if (!nextError.isEmpty()) {
    return;
  }

  const QString sampleName = obj.value(QLatin1String("name")).toString().trimmed();
  if (sampleName != m_device) {
    return;
  }

  const double nextRx = obj.value(QLatin1String("rx_bytes")).toDouble();
  const double nextTx = obj.value(QLatin1String("tx_bytes")).toDouble();
  if (m_rxBytes != nextRx) {
    m_rxBytes = nextRx;
    emit rxBytesChanged();
  }
  if (m_txBytes != nextTx) {
    m_txBytes = nextTx;
    emit txBytesChanged();
  }
  emit sampleReady(m_rxBytes, m_txBytes);
}
