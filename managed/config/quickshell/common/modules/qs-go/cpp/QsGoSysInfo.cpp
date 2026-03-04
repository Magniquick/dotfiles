#include "QsGoSysInfo.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoSysInfo::QsGoSysInfo(QObject* parent) : QObject(parent) {}

void QsGoSysInfo::setDiskDevice(const QString& v)
{
  if (m_diskDevice == v) return;
  m_diskDevice = v;
  emit diskDeviceChanged();
}

bool QsGoSysInfo::refresh()
{
  const QByteArray dev = m_diskDevice.toUtf8();

  QThreadPool::globalInstance()->start([this, dev]() {
    char* raw = QsGo_SysInfo_Refresh(dev.constData());
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) return;
      const QJsonObject obj = doc.object();

#define SET(prop, setter, key, method) \
      { auto v = obj.value(QLatin1String(key)).method; if (v != prop) { prop = v; emit setter(); } }

      SET(m_cpu,                cpuChanged,                "cpu",                toDouble())
      SET(m_mem,                memChanged,                "mem",                toInt())
      { auto v = obj.value(QLatin1String("mem_used")).toString(); if (v != m_memUsed) { m_memUsed = v; emit memUsedChanged(); } }
      { auto v = obj.value(QLatin1String("mem_total")).toString(); if (v != m_memTotal) { m_memTotal = v; emit memTotalChanged(); } }
      SET(m_disk,               diskChanged,               "disk",               toInt())
      SET(m_diskWorstCase,      diskWorstCaseChanged,      "disk_worst_case",    toInt())
      { auto v = obj.value(QLatin1String("disk_btrfs_available")).toBool(); if (v != m_diskBtrfsAvailable) { m_diskBtrfsAvailable = v; emit diskBtrfsAvailableChanged(); } }
      SET(m_diskBtrfsFreeEst,   diskBtrfsFreeEstChanged,   "disk_btrfs_free_est_gib", toDouble())
      SET(m_diskBtrfsFreeMin,   diskBtrfsFreeMinChanged,   "disk_btrfs_free_min_gib", toDouble())
      { auto v = obj.value(QLatin1String("disk_health")).toString(); if (v != m_diskHealth) { m_diskHealth = v; emit diskHealthChanged(); } }
      { auto v = obj.value(QLatin1String("disk_wear")).toString(); if (v != m_diskWear) { m_diskWear = v; emit diskWearChanged(); } }
      { auto v = obj.value(QLatin1String("disk_device")).toString(); if (v != m_diskDevice) { m_diskDevice = v; emit diskDeviceChanged(); } }
      SET(m_temp,               tempChanged,               "temp",               toDouble())
      { auto v = obj.value(QLatin1String("uptime")).toString(); if (v != m_uptime) { m_uptime = v; emit uptimeChanged(); } }
      SET(m_psiCpuSome,         psiCpuSomeChanged,         "psi_cpu_some",       toDouble())
      SET(m_psiCpuFull,         psiCpuFullChanged,         "psi_cpu_full",       toDouble())
      SET(m_psiMemSome,         psiMemSomeChanged,         "psi_mem_some",       toDouble())
      SET(m_psiMemFull,         psiMemFullChanged,         "psi_mem_full",       toDouble())
      SET(m_psiIoSome,          psiIoSomeChanged,          "psi_io_some",        toDouble())
      SET(m_psiIoFull,          psiIoFullChanged,          "psi_io_full",        toDouble())
      { auto v = obj.value(QLatin1String("error")).toString(); if (v != m_error) { m_error = v; emit errorChanged(); } }
#undef SET
    }, Qt::QueuedConnection);
  });

  return true;
}
