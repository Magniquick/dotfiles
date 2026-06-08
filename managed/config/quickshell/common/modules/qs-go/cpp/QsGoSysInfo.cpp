#include "QsGoSysInfo.h"
#include "qsgo_go_api.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QProcess>
#include <QStringList>
#include <QThreadPool>

#include <fcntl.h>
#include <linux/btrfs.h>
#include <linux/btrfs_tree.h>
#include <sys/ioctl.h>
#include <sys/statvfs.h>
#include <unistd.h>

namespace {

constexpr quint64 BTRFS_MIN_UNALLOCATED_THRESH = 16ULL * 1024ULL * 1024ULL;

struct BtrfsUsageMetrics {
  bool available = false;
  double freeEstGiB = 0.0;
  double freeMinGiB = 0.0;
  int usedPct = 0;
  int worstPct = 0;
};

auto readTrimmedFile(const QString& path) -> QString {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }
  return QString::fromUtf8(file.readAll()).trimmed();
}

auto defaultDiskDevice() -> QString {
  static const QStringList candidates = {
      QStringLiteral("/dev/nvme0n1"),
      QStringLiteral("/dev/nvme0"),
      QStringLiteral("/dev/sda"),
      QStringLiteral("/dev/vda"),
  };
  for (const QString& path : candidates) {
    if (QFileInfo::exists(path)) {
      return path;
    }
  }
  return QStringLiteral("/dev/nvme0n1");
}

auto formatGiB(double kib) -> QString {
  return QString::number(kib / 1024.0 / 1024.0, 'f', 1) + QStringLiteral("GB");
}

auto formatUptime(quint64 total) -> QString {
  const quint64 days = total / 86400;
  quint64 rem = total % 86400;
  const quint64 hours = rem / 3600;
  rem %= 3600;
  const quint64 minutes = rem / 60;

  QStringList parts;
  if (days > 0) {
    parts << QStringLiteral("%1 %2").arg(days).arg(days == 1 ? QStringLiteral("day")
                                                             : QStringLiteral("days"));
  }
  if (hours > 0) {
    parts << QStringLiteral("%1 %2").arg(hours).arg(hours == 1 ? QStringLiteral("hour")
                                                               : QStringLiteral("hours"));
  }
  if (minutes > 0 || parts.isEmpty()) {
    parts << QStringLiteral("%1 %2").arg(minutes).arg(minutes == 1 ? QStringLiteral("minute")
                                                                   : QStringLiteral("minutes"));
  }
  return parts.join(QStringLiteral(", "));
}

auto runCommand(const QString& program, const QStringList& args) -> QString {
  QProcess process;
  process.start(program, args);
  if (!process.waitForFinished(10000)) {
    return {};
  }
  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
    return {};
  }
  return QString::fromUtf8(process.readAllStandardOutput());
}

auto runSmartctl(const QStringList& args) -> QString {
  QString output = runCommand(QStringLiteral("smartctl"), args);
  if (!output.isEmpty()) {
    return output;
  }
  QStringList sudoArgs;
  sudoArgs << QStringLiteral("-n") << QStringLiteral("smartctl");
  sudoArgs << args;
  return runCommand(QStringLiteral("sudo"), sudoArgs);
}

auto runSmartctlJson(const QStringList& args) -> QJsonObject {
  QStringList jsonArgs{QStringLiteral("-j")};
  jsonArgs << args;
  const QString output = runSmartctl(jsonArgs);
  if (output.isEmpty()) {
    return {};
  }
  const QJsonDocument doc = QJsonDocument::fromJson(output.toUtf8());
  return doc.isObject() ? doc.object() : QJsonObject{};
}

auto jsonNumberString(const QJsonValue& value) -> QString {
  if (value.isDouble()) {
    return QString::number(value.toInt());
  }
  if (value.isString()) {
    return value.toString().trimmed();
  }
  return {};
}

auto jsonIntValue(const QJsonValue& value, int fallback = 0) -> int {
  bool ok = false;
  if (value.isDouble()) {
    return value.toInt();
  }
  if (value.isString()) {
    const int parsed = value.toString().trimmed().toInt(&ok, 0);
    if (ok) {
      return parsed;
    }
  }
  return fallback;
}

auto smartWearLabel(const QJsonObject& smart) -> QString {
  const QJsonObject nvme =
      smart.value(QStringLiteral("nvme_smart_health_information_log")).toObject();
  if (nvme.contains(QStringLiteral("percentage_used"))) {
    return jsonNumberString(nvme.value(QStringLiteral("percentage_used"))) + QStringLiteral("%");
  }

  const QJsonObject attrs = smart.value(QStringLiteral("ata_smart_attributes")).toObject();
  const QJsonArray table = attrs.value(QStringLiteral("table")).toArray();
  for (const QJsonValue& value : table) {
    const QJsonObject attr = value.toObject();
    const QString name = attr.value(QStringLiteral("name")).toString();
    if (!name.contains(QStringLiteral("Percentage_Used"), Qt::CaseInsensitive) &&
        !name.contains(QStringLiteral("Percent_Lifetime"), Qt::CaseInsensitive)) {
      continue;
    }
    const QJsonObject raw = attr.value(QStringLiteral("raw")).toObject();
    const QString rawValue = jsonNumberString(raw.value(QStringLiteral("value")));
    if (!rawValue.isEmpty()) {
      return rawValue + QStringLiteral("%");
    }
  }
  return QStringLiteral("Unknown");
}

auto smartHealthLabel(const QJsonObject& smart) -> QString {
  const QJsonObject status = smart.value(QStringLiteral("smart_status")).toObject();
  const bool hasPassed = status.contains(QStringLiteral("passed"));
  const bool passed = status.value(QStringLiteral("passed")).toBool(false);
  const QJsonObject nvme =
      smart.value(QStringLiteral("nvme_smart_health_information_log")).toObject();
  const int criticalWarning = jsonIntValue(nvme.value(QStringLiteral("critical_warning")), 0);
  if (hasPassed && passed && criticalWarning == 0) {
    return QStringLiteral("Healthy");
  }
  if (hasPassed && !passed) {
    return QStringLiteral("Failed");
  }
  if (criticalWarning != 0) {
    return QStringLiteral("Warning (%1)").arg(criticalWarning);
  }
  return QStringLiteral("Unknown");
}

auto btrfsCopiesForFlags(quint64 flags) -> int {
  if ((flags & BTRFS_BLOCK_GROUP_RAID1C4) != 0U) {
    return 4;
  }
  if ((flags & BTRFS_BLOCK_GROUP_RAID1C3) != 0U) {
    return 3;
  }
  if ((flags & BTRFS_BLOCK_GROUP_RAID10) != 0U) {
    return 2;
  }
  if ((flags & BTRFS_BLOCK_GROUP_RAID1) != 0U) {
    return 2;
  }
  if ((flags & BTRFS_BLOCK_GROUP_DUP) != 0U) {
    return 2;
  }
  if ((flags & BTRFS_BLOCK_GROUP_RAID56_MASK) != 0U) {
    return 0;
  }
  return 1;
}

auto loadBtrfsSpaceInfo(int fd, QByteArray& storage) -> bool {
  struct btrfs_ioctl_space_args header{};
  if (ioctl(fd, BTRFS_IOC_SPACE_INFO, &header) < 0) {
    return false;
  }
  if (header.total_spaces == 0) {
    return false;
  }

  storage.resize(static_cast<int>(sizeof(struct btrfs_ioctl_space_args) +
                                  (header.total_spaces * sizeof(struct btrfs_ioctl_space_info))));
  auto* args = reinterpret_cast<struct btrfs_ioctl_space_args*>(storage.data());
  memset(args, 0, static_cast<size_t>(storage.size()));
  args->space_slots = header.total_spaces;
  return ioctl(fd, BTRFS_IOC_SPACE_INFO, args) >= 0;
}

auto loadBtrfsDeviceSize(int fd) -> quint64 {
  struct btrfs_ioctl_fs_info_args fsInfo{};
  if (ioctl(fd, BTRFS_IOC_FS_INFO, &fsInfo) < 0) {
    return 0;
  }

  quint64 totalSize = 0;
  for (quint64 devid = 1; devid <= fsInfo.max_id; ++devid) {
    struct btrfs_ioctl_dev_info_args deviceInfo{};
    deviceInfo.devid = devid;
    if (ioctl(fd, BTRFS_IOC_DEV_INFO, &deviceInfo) == 0) {
      totalSize += static_cast<quint64>(deviceInfo.total_bytes);
    }
  }
  return totalSize;
}

auto readBtrfsUsageMetrics() -> BtrfsUsageMetrics {
  BtrfsUsageMetrics metrics;

  const int fd = ::open("/", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return metrics;
  }

  QByteArray storage;
  const bool spaceOk = loadBtrfsSpaceInfo(fd, storage);
  const quint64 totalSize = loadBtrfsDeviceSize(fd);
  ::close(fd);

  if (!spaceOk || totalSize == 0) {
    return metrics;
  }

  const auto* spaceArgs =
      reinterpret_cast<const struct btrfs_ioctl_space_args*>(storage.constData());

  quint64 rawDataUsed = 0;
  quint64 rawDataChunks = 0;
  quint64 logicalDataChunks = 0;
  quint64 rawMetadataUsed = 0;
  quint64 rawMetadataChunks = 0;
  quint64 logicalMetadataChunks = 0;
  quint64 rawSystemUsed = 0;
  quint64 rawSystemChunks = 0;
  quint64 globalReserve = 0;
  quint64 globalReserveUsed = 0;
  double maxDataRatio = 1.0;
  bool mixed = false;

  for (quint64 i = 0; i < spaceArgs->total_spaces; ++i) {
    const auto& space = spaceArgs->spaces[i];
    const quint64 flags = space.flags;
    const int copies = btrfsCopiesForFlags(flags);
    if (copies == 0) {
      return metrics;
    }

    if (copies > maxDataRatio) {
      maxDataRatio = static_cast<double>(copies);
    }

    if ((flags & BTRFS_SPACE_INFO_GLOBAL_RSV) != 0U) {
      globalReserve = static_cast<quint64>(space.total_bytes);
      globalReserveUsed = static_cast<quint64>(space.used_bytes);
    }

    if ((flags & (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)) ==
        (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)) {
      mixed = true;
    }

    if ((flags & BTRFS_BLOCK_GROUP_DATA) != 0U) {
      rawDataUsed += static_cast<quint64>(space.used_bytes) * static_cast<quint64>(copies);
      rawDataChunks += static_cast<quint64>(space.total_bytes) * static_cast<quint64>(copies);
      logicalDataChunks += static_cast<quint64>(space.total_bytes);
    }
    if ((flags & BTRFS_BLOCK_GROUP_METADATA) != 0U) {
      rawMetadataUsed += static_cast<quint64>(space.used_bytes) * static_cast<quint64>(copies);
      rawMetadataChunks += static_cast<quint64>(space.total_bytes) * static_cast<quint64>(copies);
      logicalMetadataChunks += static_cast<quint64>(space.total_bytes);
    }
    if ((flags & BTRFS_BLOCK_GROUP_SYSTEM) != 0U) {
      rawSystemUsed += static_cast<quint64>(space.used_bytes) * static_cast<quint64>(copies);
      rawSystemChunks += static_cast<quint64>(space.total_bytes) * static_cast<quint64>(copies);
    }
  }

  const quint64 rawTotalChunks = rawDataChunks + rawSystemChunks + (mixed ? 0 : rawMetadataChunks);
  const quint64 rawTotalUsed = rawDataUsed + rawSystemUsed + (mixed ? 0 : rawMetadataUsed);
  const quint64 rawTotalUnused = totalSize > rawTotalChunks ? totalSize - rawTotalChunks : 0;
  if (logicalDataChunks == 0 || rawDataChunks == 0) {
    return metrics;
  }

  const double dataRatio =
      static_cast<double>(rawDataChunks) / static_cast<double>(logicalDataChunks);
  double freeEstimated = static_cast<double>(rawDataChunks - rawDataUsed) / dataRatio;
  if (mixed) {
    freeEstimated -= static_cast<double>(
        globalReserve > globalReserveUsed ? globalReserve - globalReserveUsed : 0);
  }
  double freeMin = freeEstimated;
  if (rawTotalUnused >= BTRFS_MIN_UNALLOCATED_THRESH) {
    freeEstimated += static_cast<double>(rawTotalUnused) / dataRatio;
    freeMin += static_cast<double>(rawTotalUnused) / maxDataRatio;
  }

  freeEstimated = qMax(0.0, freeEstimated);
  freeMin = qMax(0.0, freeMin);

  metrics.available = true;
  metrics.freeEstGiB = freeEstimated / 1024.0 / 1024.0 / 1024.0;
  metrics.freeMinGiB = freeMin / 1024.0 / 1024.0 / 1024.0;
  metrics.usedPct = static_cast<int>((100.0 * static_cast<double>(rawTotalUsed)) /
                                     static_cast<double>(totalSize));
  metrics.worstPct = static_cast<int>((1.0 - (freeMin / static_cast<double>(totalSize))) * 100.0);
  metrics.usedPct = qBound(0, metrics.usedPct, 100);
  metrics.worstPct = qBound(0, metrics.worstPct, 100);
  return metrics;
}

} // namespace

QsGoSysInfo::QsGoSysInfo(QObject* parent) : QObject(parent) {
  if (m_diskDevice.isEmpty()) {
    m_diskDevice = defaultDiskDevice();
  }
}

void QsGoSysInfo::setDiskDevice(const QString& value) {
  const QString next = value.isEmpty() ? defaultDiskDevice() : value;
  if (m_diskDevice == next) {
    return;
  }
  m_diskDevice = next;
  emit diskDeviceChanged();
}

void QsGoSysInfo::applySnapshot(double cpu, int mem, const QString& memUsed,
                                const QString& memTotal, int disk, int diskWorstCase,
                                bool diskBtrfsAvailable, double diskBtrfsFreeEst,
                                double diskBtrfsFreeMin, const QString& diskHealth,
                                const QString& diskWear, const QString& diskDevice, double temp,
                                const QString& uptime, double psiCpuSome, double psiCpuFull,
                                double psiMemSome, double psiMemFull, double psiIoSome,
                                double psiIoFull, const QString& error) {
#define SET_SCALAR(member, value, signalName)                                                      \
  if ((member) != (value)) {                                                                       \
    (member) = value;                                                                              \
    emit signalName();                                                                             \
  }

  SET_SCALAR(m_cpu, cpu, cpuChanged)
  SET_SCALAR(m_mem, mem, memChanged)
  SET_SCALAR(m_disk, disk, diskChanged)
  SET_SCALAR(m_diskWorstCase, diskWorstCase, diskWorstCaseChanged)
  SET_SCALAR(m_diskBtrfsAvailable, diskBtrfsAvailable, diskBtrfsAvailableChanged)
  SET_SCALAR(m_diskBtrfsFreeEst, diskBtrfsFreeEst, diskBtrfsFreeEstChanged)
  SET_SCALAR(m_diskBtrfsFreeMin, diskBtrfsFreeMin, diskBtrfsFreeMinChanged)
  SET_SCALAR(m_temp, temp, tempChanged)
  SET_SCALAR(m_psiCpuSome, psiCpuSome, psiCpuSomeChanged)
  SET_SCALAR(m_psiCpuFull, psiCpuFull, psiCpuFullChanged)
  SET_SCALAR(m_psiMemSome, psiMemSome, psiMemSomeChanged)
  SET_SCALAR(m_psiMemFull, psiMemFull, psiMemFullChanged)
  SET_SCALAR(m_psiIoSome, psiIoSome, psiIoSomeChanged)
  SET_SCALAR(m_psiIoFull, psiIoFull, psiIoFullChanged)
#undef SET_SCALAR

  if (m_memUsed != memUsed) {
    m_memUsed = memUsed;
    emit memUsedChanged();
  }
  if (m_memTotal != memTotal) {
    m_memTotal = memTotal;
    emit memTotalChanged();
  }
  if (m_diskHealth != diskHealth) {
    m_diskHealth = diskHealth;
    emit diskHealthChanged();
  }
  if (m_diskWear != diskWear) {
    m_diskWear = diskWear;
    emit diskWearChanged();
  }
  if (m_diskDevice != diskDevice) {
    m_diskDevice = diskDevice;
    emit diskDeviceChanged();
  }
  if (m_uptime != uptime) {
    m_uptime = uptime;
    emit uptimeChanged();
  }
  if (m_error != error) {
    m_error = error;
    emit errorChanged();
  }
}

auto QsGoSysInfo::refresh() -> bool {
  const QString diskDevice = m_diskDevice.isEmpty() ? defaultDiskDevice() : m_diskDevice;
  QThreadPool::globalInstance()->start([this, diskDevice]() -> void {
    QStringList errors;

    char* rawStats = QsGo_SysStats_Snapshot();
    QByteArray const statsJson(rawStats);
    QsGo_Free(rawStats);
    const QJsonDocument statsDoc = QJsonDocument::fromJson(statsJson);
    const QJsonObject stats = statsDoc.isObject() ? statsDoc.object() : QJsonObject{};
    if (stats.isEmpty()) {
      errors << QStringLiteral("invalid sysstats response");
    }

    const QJsonArray statsErrors = stats.value(QLatin1String("errors")).toArray();
    for (const QJsonValue& value : statsErrors) {
      const QString error = value.toString().trimmed();
      if (!error.isEmpty()) {
        errors << error;
      }
    }

    double cpu = m_cpu;
    const double total = stats.value(QLatin1String("cpu_total")).toDouble();
    const double idle = stats.value(QLatin1String("cpu_idle")).toDouble();
    if (m_lastCpuTotal != 0.0 && total > m_lastCpuTotal) {
      const double dt = total - m_lastCpuTotal;
      const double di = qBound(0.0, idle - m_lastCpuIdle, dt);
      cpu = 100.0 * (1.0 - (di / dt));
    }

    int mem = 0;
    QString memUsed;
    QString memTotal;
    {
      const quint64 totalKB =
          static_cast<quint64>(qMax(0.0, stats.value(QLatin1String("mem_total_kib")).toDouble()));
      const quint64 availKB = static_cast<quint64>(
          qMax(0.0, stats.value(QLatin1String("mem_available_kib")).toDouble()));
      if (totalKB > 0) {
        const quint64 usedKB = totalKB - availKB;
        mem =
            static_cast<int>((100.0 * static_cast<double>(usedKB)) / static_cast<double>(totalKB));
        memUsed = formatGiB(static_cast<double>(usedKB));
        memTotal = formatGiB(static_cast<double>(totalKB));
      } else {
        errors << QStringLiteral("MemTotal is zero");
      }
    }

    int disk = 0;
    {
      struct statvfs stats{};
      if (statvfs("/", &stats) == 0) {
        const double totalBytes =
            static_cast<double>(stats.f_blocks) * static_cast<double>(stats.f_frsize);
        const double availBytes =
            static_cast<double>(stats.f_bavail) * static_cast<double>(stats.f_frsize);
        const double usedBytes = totalBytes - availBytes;
        if (totalBytes > 0.0) {
          disk = static_cast<int>((100.0 * usedBytes) / totalBytes);
        }
      } else {
        errors << QStringLiteral("failed to stat filesystem");
      }
    }

    bool diskBtrfsAvailable = false;
    double diskBtrfsFreeEst = 0;
    double diskBtrfsFreeMin = 0;
    int diskWorstCase = disk;
    if (stats.value(QLatin1String("root_fs_type")).toString() == QStringLiteral("btrfs")) {
      const qint64 now = QDateTime::currentMSecsSinceEpoch();
      if (now - m_lastBtrfsMs > 30000) {
        const BtrfsUsageMetrics metrics = readBtrfsUsageMetrics();
        m_btrfsAvailableCache = metrics.available;
        if (metrics.available) {
          m_btrfsDiskCache = metrics.usedPct;
          m_btrfsFreeEstCache = metrics.freeEstGiB;
          m_btrfsFreeMinCache = metrics.freeMinGiB;
          m_btrfsWorstCaseCache = metrics.worstPct;
        }
        m_lastBtrfsMs = now;
      }

      diskBtrfsAvailable = m_btrfsAvailableCache;
      diskBtrfsFreeEst = m_btrfsFreeEstCache;
      diskBtrfsFreeMin = m_btrfsFreeMinCache;
      if (m_btrfsAvailableCache) {
        disk = m_btrfsDiskCache;
        diskWorstCase = m_btrfsWorstCaseCache;
      }
    }

    double temp = 0.0;
    {
      const QStringList entries =
          QDir().entryList({QStringLiteral("/sys/class/thermal/thermal_zone*/temp")}, QDir::Files);
      Q_UNUSED(entries);
      const QStringList thermalEntries =
          QDir(QStringLiteral("/sys/class/thermal"))
              .entryList({QStringLiteral("thermal_zone*")}, QDir::Dirs | QDir::NoDotAndDotDot,
                         QDir::Name);
      auto readZoneTemp = [](const QString& zoneDir) -> double {
        bool ok = false;
        const double raw = readTrimmedFile(zoneDir + QStringLiteral("/temp")).toDouble(&ok);
        return ok ? raw / 1000.0 : 0.0;
      };
      for (const QString& entry : thermalEntries) {
        const QString zoneDir = QStringLiteral("/sys/class/thermal/") + entry;
        if (readTrimmedFile(zoneDir + QStringLiteral("/type")) == QStringLiteral("x86_pkg_temp")) {
          temp = readZoneTemp(zoneDir);
          if (temp > 0.0) {
            break;
          }
        }
      }
      if (temp <= 0.0) {
        for (const QString& entry : thermalEntries) {
          temp = readZoneTemp(QStringLiteral("/sys/class/thermal/") + entry);
          if (temp > 0.0) {
            break;
          }
        }
      }
    }

    const QString uptime = formatUptime(
        static_cast<quint64>(qMax(0.0, stats.value(QLatin1String("uptime_seconds")).toDouble())));
    const double psiCpuSome = stats.value(QLatin1String("psi_cpu_some")).toDouble();
    const double psiCpuFull = stats.value(QLatin1String("psi_cpu_full")).toDouble();
    const double psiMemSome = stats.value(QLatin1String("psi_mem_some")).toDouble();
    const double psiMemFull = stats.value(QLatin1String("psi_mem_full")).toDouble();
    const double psiIoSome = stats.value(QLatin1String("psi_io_some")).toDouble();
    const double psiIoFull = stats.value(QLatin1String("psi_io_full")).toDouble();

    QString diskHealth = m_diskHealthCache;
    QString diskWear = m_diskWearCache;
    {
      const qint64 now = QDateTime::currentMSecsSinceEpoch();
      if (m_diskHealthCache.isEmpty() || now - m_lastDiskHealthMs > (6LL * 60LL * 60LL * 1000LL)) {
        const QJsonObject smart =
            runSmartctlJson({QStringLiteral("--attributes"), QStringLiteral("--health"),
                             QStringLiteral("--tolerance=conservative"), diskDevice});

        if (smart.isEmpty()) {
          m_diskHealthCache = QStringLiteral("Unknown (smartctl missing)");
          m_diskWearCache = QStringLiteral("Unknown");
        } else {
          m_diskHealthCache = smartHealthLabel(smart);
          m_diskWearCache = smartWearLabel(smart);
        }
        m_lastDiskHealthMs = now;
      }
      diskHealth = m_diskHealthCache;
      diskWear = m_diskWearCache;
    }

    const QString error = errors.join(QStringLiteral("; "));
    QMetaObject::invokeMethod(
        this,
        [this, cpu, mem, memUsed, memTotal, disk, diskWorstCase, diskBtrfsAvailable,
         diskBtrfsFreeEst, diskBtrfsFreeMin, diskHealth, diskWear, diskDevice, temp, uptime,
         psiCpuSome, psiCpuFull, psiMemSome, psiMemFull, psiIoSome, psiIoFull, error, total,
         idle]() -> void {
          m_lastCpuTotal = total;
          m_lastCpuIdle = idle;
          applySnapshot(cpu, mem, memUsed, memTotal, disk, diskWorstCase, diskBtrfsAvailable,
                        diskBtrfsFreeEst, diskBtrfsFreeMin, diskHealth, diskWear, diskDevice, temp,
                        uptime, psiCpuSome, psiCpuFull, psiMemSome, psiMemFull, psiIoSome,
                        psiIoFull, error);
        },
        Qt::QueuedConnection);
  });

  return true;
}
