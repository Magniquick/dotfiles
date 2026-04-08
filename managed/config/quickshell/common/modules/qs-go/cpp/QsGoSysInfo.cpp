#include "QsGoSysInfo.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStorageInfo>
#include <QStringList>
#include <QTextStream>
#include <QThreadPool>
#include <QVector>

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

QString readTrimmedFile(const QString& path) {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
    return {};
  return QString::fromUtf8(file.readAll()).trimmed();
}

QString defaultDiskDevice() {
  static const QStringList candidates = {
      QStringLiteral("/dev/nvme0n1"),
      QStringLiteral("/dev/nvme0"),
      QStringLiteral("/dev/sda"),
      QStringLiteral("/dev/vda"),
  };
  for (const QString& path : candidates) {
    if (QFileInfo::exists(path))
      return path;
  }
  return QStringLiteral("/dev/nvme0n1");
}

QString formatGiB(double kib) {
  return QString::number(kib / 1024.0 / 1024.0, 'f', 1) + QStringLiteral("GB");
}

QString formatUptime(quint64 total) {
  const quint64 days = total / 86400;
  quint64 rem = total % 86400;
  const quint64 hours = rem / 3600;
  rem %= 3600;
  const quint64 minutes = rem / 60;

  QStringList parts;
  if (days > 0)
    parts << QStringLiteral("%1 %2").arg(days).arg(days == 1 ? QStringLiteral("day")
                                                             : QStringLiteral("days"));
  if (hours > 0)
    parts << QStringLiteral("%1 %2").arg(hours).arg(hours == 1 ? QStringLiteral("hour")
                                                               : QStringLiteral("hours"));
  if (minutes > 0 || parts.isEmpty())
    parts << QStringLiteral("%1 %2").arg(minutes).arg(minutes == 1 ? QStringLiteral("minute")
                                                                   : QStringLiteral("minutes"));
  return parts.join(QStringLiteral(", "));
}

QString runCommand(const QString& program, const QStringList& args) {
  QProcess process;
  process.start(program, args);
  if (!process.waitForFinished(10000))
    return {};
  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
    return {};
  return QString::fromUtf8(process.readAllStandardOutput());
}

QString runSmartctl(const QStringList& args) {
  QString output = runCommand(QStringLiteral("smartctl"), args);
  if (!output.isEmpty())
    return output;
  QStringList sudoArgs;
  sudoArgs << QStringLiteral("-n") << QStringLiteral("smartctl");
  sudoArgs << args;
  return runCommand(QStringLiteral("sudo"), sudoArgs);
}

QString parseSmartctlValue(const QString& output, const QString& needle) {
  const QStringList lines = output.split(QLatin1Char('\n'));
  for (const QString& line : lines) {
    if (!line.contains(needle))
      continue;
    const int index = line.indexOf(needle);
    return line.mid(index + needle.size())
        .trimmed()
        .remove(QRegularExpression(QStringLiteral("^:+|:+$")));
  }
  return {};
}

QString normalizeSmartToken(QString value) {
  value = value.trimmed();
  if (value.isEmpty())
    return {};
  const QStringList fields =
      value.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
  if (!fields.isEmpty())
    value = fields.first();
  value = value.remove(QRegularExpression(QStringLiteral("^[():]+|[():]+$")));
  return value.toUpper();
}

bool isZeroCriticalWarning(QString value) {
  value = value.trimmed().toUpper();
  if (value.startsWith(QStringLiteral("0X")))
    value = value.mid(2);
  value.remove(QRegularExpression(QStringLiteral("^0+")));
  return value.isEmpty();
}

bool rootIsBtrfs() {
  const QString mounts = readTrimmedFile(QStringLiteral("/proc/self/mounts"));
  const QStringList lines = mounts.split(QLatin1Char('\n'));
  for (const QString& line : lines) {
    const QStringList fields =
        line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
    if (fields.size() >= 3 && fields.at(1) == QStringLiteral("/"))
      return fields.at(2) == QStringLiteral("btrfs");
  }
  return false;
}

int btrfsCopiesForFlags(quint64 flags) {
  if (flags & BTRFS_BLOCK_GROUP_RAID1C4)
    return 4;
  if (flags & BTRFS_BLOCK_GROUP_RAID1C3)
    return 3;
  if (flags & BTRFS_BLOCK_GROUP_RAID10)
    return 2;
  if (flags & BTRFS_BLOCK_GROUP_RAID1)
    return 2;
  if (flags & BTRFS_BLOCK_GROUP_DUP)
    return 2;
  if (flags & BTRFS_BLOCK_GROUP_RAID56_MASK)
    return 0;
  return 1;
}

bool loadBtrfsSpaceInfo(int fd, QByteArray& storage) {
  struct btrfs_ioctl_space_args header{};
  if (ioctl(fd, BTRFS_IOC_SPACE_INFO, &header) < 0)
    return false;
  if (header.total_spaces == 0)
    return false;

  storage.resize(int(sizeof(struct btrfs_ioctl_space_args) +
                     header.total_spaces * sizeof(struct btrfs_ioctl_space_info)));
  auto* args = reinterpret_cast<struct btrfs_ioctl_space_args*>(storage.data());
  memset(args, 0, size_t(storage.size()));
  args->space_slots = header.total_spaces;
  if (ioctl(fd, BTRFS_IOC_SPACE_INFO, args) < 0)
    return false;
  return true;
}

quint64 loadBtrfsDeviceSize(int fd) {
  struct btrfs_ioctl_fs_info_args fsInfo{};
  if (ioctl(fd, BTRFS_IOC_FS_INFO, &fsInfo) < 0)
    return 0;

  quint64 totalSize = 0;
  for (quint64 devid = 1; devid <= fsInfo.max_id; ++devid) {
    struct btrfs_ioctl_dev_info_args deviceInfo{};
    deviceInfo.devid = devid;
    if (ioctl(fd, BTRFS_IOC_DEV_INFO, &deviceInfo) == 0)
      totalSize += quint64(deviceInfo.total_bytes);
  }
  return totalSize;
}

BtrfsUsageMetrics readBtrfsUsageMetrics() {
  BtrfsUsageMetrics metrics;

  const int fd = ::open("/", O_RDONLY | O_CLOEXEC);
  if (fd < 0)
    return metrics;

  QByteArray storage;
  const bool spaceOk = loadBtrfsSpaceInfo(fd, storage);
  const quint64 totalSize = loadBtrfsDeviceSize(fd);
  ::close(fd);

  if (!spaceOk || totalSize == 0)
    return metrics;

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
    if (copies == 0)
      return metrics;

    if (copies > maxDataRatio)
      maxDataRatio = double(copies);

    if (flags & BTRFS_SPACE_INFO_GLOBAL_RSV) {
      globalReserve = quint64(space.total_bytes);
      globalReserveUsed = quint64(space.used_bytes);
    }

    if ((flags & (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)) ==
        (BTRFS_BLOCK_GROUP_DATA | BTRFS_BLOCK_GROUP_METADATA)) {
      mixed = true;
    }

    if (flags & BTRFS_BLOCK_GROUP_DATA) {
      rawDataUsed += quint64(space.used_bytes) * quint64(copies);
      rawDataChunks += quint64(space.total_bytes) * quint64(copies);
      logicalDataChunks += quint64(space.total_bytes);
    }
    if (flags & BTRFS_BLOCK_GROUP_METADATA) {
      rawMetadataUsed += quint64(space.used_bytes) * quint64(copies);
      rawMetadataChunks += quint64(space.total_bytes) * quint64(copies);
      logicalMetadataChunks += quint64(space.total_bytes);
    }
    if (flags & BTRFS_BLOCK_GROUP_SYSTEM) {
      rawSystemUsed += quint64(space.used_bytes) * quint64(copies);
      rawSystemChunks += quint64(space.total_bytes) * quint64(copies);
    }
  }

  const quint64 rawTotalChunks = rawDataChunks + rawSystemChunks + (mixed ? 0 : rawMetadataChunks);
  const quint64 rawTotalUsed = rawDataUsed + rawSystemUsed + (mixed ? 0 : rawMetadataUsed);
  const quint64 rawTotalUnused = totalSize > rawTotalChunks ? totalSize - rawTotalChunks : 0;
  if (logicalDataChunks == 0 || rawDataChunks == 0)
    return metrics;

  const double dataRatio = double(rawDataChunks) / double(logicalDataChunks);
  double freeEstimated = double(rawDataChunks - rawDataUsed) / dataRatio;
  if (mixed)
    freeEstimated -=
        double(globalReserve > globalReserveUsed ? globalReserve - globalReserveUsed : 0);
  double freeMin = freeEstimated;
  if (rawTotalUnused >= BTRFS_MIN_UNALLOCATED_THRESH) {
    freeEstimated += double(rawTotalUnused) / dataRatio;
    freeMin += double(rawTotalUnused) / maxDataRatio;
  }

  freeEstimated = qMax(0.0, freeEstimated);
  freeMin = qMax(0.0, freeMin);

  metrics.available = true;
  metrics.freeEstGiB = freeEstimated / 1024.0 / 1024.0 / 1024.0;
  metrics.freeMinGiB = freeMin / 1024.0 / 1024.0 / 1024.0;
  metrics.usedPct = int((100.0 * double(rawTotalUsed)) / double(totalSize));
  metrics.worstPct = int((1.0 - (freeMin / double(totalSize))) * 100.0);
  metrics.usedPct = qBound(0, metrics.usedPct, 100);
  metrics.worstPct = qBound(0, metrics.worstPct, 100);
  return metrics;
}

} // namespace

QsGoSysInfo::QsGoSysInfo(QObject* parent) : QObject(parent) {
  if (m_diskDevice.isEmpty())
    m_diskDevice = defaultDiskDevice();
}

void QsGoSysInfo::setDiskDevice(const QString& value) {
  const QString next = value.isEmpty() ? defaultDiskDevice() : value;
  if (m_diskDevice == next)
    return;
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
  if (member != value) {                                                                           \
    member = value;                                                                                \
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

bool QsGoSysInfo::refresh() {
  const QString diskDevice = m_diskDevice.isEmpty() ? defaultDiskDevice() : m_diskDevice;
  QThreadPool::globalInstance()->start([this, diskDevice]() {
    QStringList errors;

    double cpu = m_cpu;
    quint64 total = 0;
    quint64 idle = 0;
    {
      const QString line =
          readTrimmedFile(QStringLiteral("/proc/stat")).section(QLatin1Char('\n'), 0, 0);
      const QStringList fields =
          line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
      if (fields.size() >= 5 && fields.first() == QStringLiteral("cpu")) {
        QVector<quint64> values;
        for (int i = 1; i < fields.size(); ++i)
          values.append(fields.at(i).toULongLong());
        for (quint64 value : values)
          total += value;
        if (values.size() >= 5)
          idle = values.at(3) + values.at(4);
        if (m_lastCpuTotal != 0 && total > m_lastCpuTotal) {
          const quint64 dt = total - m_lastCpuTotal;
          const quint64 di = qMin(idle - m_lastCpuIdle, dt);
          cpu = 100.0 * (1.0 - (double(di) / double(dt)));
        }
      } else {
        errors << QStringLiteral("malformed /proc/stat");
      }
    }

    int mem = 0;
    QString memUsed;
    QString memTotal;
    {
      quint64 totalKB = 0;
      quint64 availKB = 0;
      const QStringList lines =
          readTrimmedFile(QStringLiteral("/proc/meminfo")).split(QLatin1Char('\n'));
      for (const QString& line : lines) {
        if (line.startsWith(QStringLiteral("MemTotal:")))
          totalKB = line.mid(QStringLiteral("MemTotal:").size())
                        .trimmed()
                        .section(QLatin1Char(' '), 0, 0)
                        .toULongLong();
        else if (line.startsWith(QStringLiteral("MemAvailable:")))
          availKB = line.mid(QStringLiteral("MemAvailable:").size())
                        .trimmed()
                        .section(QLatin1Char(' '), 0, 0)
                        .toULongLong();
      }
      if (totalKB > 0) {
        const quint64 usedKB = totalKB - availKB;
        mem = int((100.0 * double(usedKB)) / double(totalKB));
        memUsed = formatGiB(double(usedKB));
        memTotal = formatGiB(double(totalKB));
      } else {
        errors << QStringLiteral("MemTotal is zero");
      }
    }

    int disk = 0;
    {
      struct statvfs stats{};
      if (statvfs("/", &stats) == 0) {
        const double totalBytes = double(stats.f_blocks) * double(stats.f_frsize);
        const double availBytes = double(stats.f_bavail) * double(stats.f_frsize);
        const double usedBytes = totalBytes - availBytes;
        if (totalBytes > 0.0)
          disk = int((100.0 * usedBytes) / totalBytes);
      } else {
        errors << QStringLiteral("failed to stat filesystem");
      }
    }

    bool diskBtrfsAvailable = false;
    double diskBtrfsFreeEst = 0;
    double diskBtrfsFreeMin = 0;
    int diskWorstCase = disk;
    if (rootIsBtrfs()) {
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
          if (temp > 0.0)
            break;
        }
      }
      if (temp <= 0.0) {
        for (const QString& entry : thermalEntries) {
          temp = readZoneTemp(QStringLiteral("/sys/class/thermal/") + entry);
          if (temp > 0.0)
            break;
        }
      }
    }

    QString uptime;
    {
      bool ok = false;
      const double secs = readTrimmedFile(QStringLiteral("/proc/uptime"))
                              .section(QLatin1Char(' '), 0, 0)
                              .toDouble(&ok);
      uptime = ok ? formatUptime(quint64(secs)) : QString();
    }

    auto readPsi = [](const QString& path) -> QPair<double, double> {
      double some = 0.0;
      double full = 0.0;
      const QStringList lines = readTrimmedFile(path).split(QLatin1Char('\n'));
      for (const QString& line : lines) {
        const QStringList fields =
            line.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
        for (const QString& field : fields) {
          if (!field.startsWith(QStringLiteral("avg10=")))
            continue;
          const double value = field.mid(QStringLiteral("avg10=").size()).toDouble();
          if (line.startsWith(QStringLiteral("some")))
            some = value;
          else
            full = value;
        }
      }
      return {some, full};
    };
    const auto psiCpu = readPsi(QStringLiteral("/proc/pressure/cpu"));
    const auto psiMem = readPsi(QStringLiteral("/proc/pressure/memory"));
    const auto psiIo = readPsi(QStringLiteral("/proc/pressure/io"));

    QString diskHealth = m_diskHealthCache;
    QString diskWear = m_diskWearCache;
    {
      const qint64 now = QDateTime::currentMSecsSinceEpoch();
      if (m_diskHealthCache.isEmpty() || now - m_lastDiskHealthMs > (6LL * 60LL * 60LL * 1000LL)) {
        const QString attrs = runSmartctl({QStringLiteral("--attributes"), diskDevice});
        const QString healthOutput = runSmartctl(
            {QStringLiteral("--health"), QStringLiteral("--tolerance=conservative"), diskDevice});

        if (attrs.isEmpty() && healthOutput.isEmpty()) {
          m_diskHealthCache = QStringLiteral("Unknown (smartctl missing)");
          m_diskWearCache = QStringLiteral("Unknown");
        } else {
          QString critWarn = parseSmartctlValue(attrs, QStringLiteral("Critical Warning:"));
          if (critWarn.isEmpty())
            critWarn = QStringLiteral("unknown");
          QString wear = parseSmartctlValue(attrs, QStringLiteral("Percentage Used:"));
          if (wear.isEmpty())
            wear = QStringLiteral("Unknown");

          QString healthResult = parseSmartctlValue(healthOutput, QStringLiteral("result"));
          if (healthResult.isEmpty())
            healthResult = parseSmartctlValue(healthOutput, QStringLiteral("SMART Health Status:"));
          if (healthResult.isEmpty())
            healthResult = QStringLiteral("unknown");

          const QString healthNorm = normalizeSmartToken(healthResult);
          const QString critWarnNorm = normalizeSmartToken(critWarn);
          if (healthNorm == QStringLiteral("PASSED") && isZeroCriticalWarning(critWarnNorm))
            m_diskHealthCache = QStringLiteral("Healthy");
          else if (healthResult != QStringLiteral("unknown"))
            m_diskHealthCache = QStringLiteral("%1 (%2)").arg(healthResult, critWarn);
          else
            m_diskHealthCache = QStringLiteral("Unknown (%1)").arg(critWarn);
          m_diskWearCache = wear;
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
         diskBtrfsFreeEst, diskBtrfsFreeMin, diskHealth, diskWear, diskDevice, temp, uptime, psiCpu,
         psiMem, psiIo, error, total, idle]() {
          m_lastCpuTotal = total;
          m_lastCpuIdle = idle;
          applySnapshot(cpu, mem, memUsed, memTotal, disk, diskWorstCase, diskBtrfsAvailable,
                        diskBtrfsFreeEst, diskBtrfsFreeMin, diskHealth, diskWear, diskDevice, temp,
                        uptime, psiCpu.first, psiCpu.second, psiMem.first, psiMem.second,
                        psiIo.first, psiIo.second, error);
        },
        Qt::QueuedConnection);
  });

  return true;
}
