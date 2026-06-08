#pragma once
#include <QObject>

class QsGoSysInfo : public QObject {
  Q_OBJECT

  Q_PROPERTY(double cpu READ cpu NOTIFY cpuChanged)
  Q_PROPERTY(int mem READ mem NOTIFY memChanged)
  Q_PROPERTY(QString mem_used READ memUsed NOTIFY memUsedChanged)
  Q_PROPERTY(QString mem_total READ memTotal NOTIFY memTotalChanged)
  Q_PROPERTY(int disk READ disk NOTIFY diskChanged)
  Q_PROPERTY(int disk_worst_case READ diskWorstCase NOTIFY diskWorstCaseChanged)
  Q_PROPERTY(bool disk_btrfs_available READ diskBtrfsAvailable NOTIFY diskBtrfsAvailableChanged)
  Q_PROPERTY(double disk_btrfs_free_est_gib READ diskBtrfsFreeEst NOTIFY diskBtrfsFreeEstChanged)
  Q_PROPERTY(double disk_btrfs_free_min_gib READ diskBtrfsFreeMin NOTIFY diskBtrfsFreeMinChanged)
  Q_PROPERTY(QString disk_health READ diskHealth NOTIFY diskHealthChanged)
  Q_PROPERTY(QString disk_wear READ diskWear NOTIFY diskWearChanged)
  Q_PROPERTY(QString disk_device READ diskDevice WRITE setDiskDevice NOTIFY diskDeviceChanged)
  Q_PROPERTY(double temp READ temp NOTIFY tempChanged)
  Q_PROPERTY(QString uptime READ uptime NOTIFY uptimeChanged)
  Q_PROPERTY(double psi_cpu_some READ psiCpuSome NOTIFY psiCpuSomeChanged)
  Q_PROPERTY(double psi_cpu_full READ psiCpuFull NOTIFY psiCpuFullChanged)
  Q_PROPERTY(double psi_mem_some READ psiMemSome NOTIFY psiMemSomeChanged)
  Q_PROPERTY(double psi_mem_full READ psiMemFull NOTIFY psiMemFullChanged)
  Q_PROPERTY(double psi_io_some READ psiIoSome NOTIFY psiIoSomeChanged)
  Q_PROPERTY(double psi_io_full READ psiIoFull NOTIFY psiIoFullChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsGoSysInfo(QObject* parent = nullptr);

  [[nodiscard]] auto cpu() const -> double {
    return m_cpu;
  }
  [[nodiscard]] auto mem() const -> int {
    return m_mem;
  }
  [[nodiscard]] auto memUsed() const -> QString {
    return m_memUsed;
  }
  [[nodiscard]] auto memTotal() const -> QString {
    return m_memTotal;
  }
  [[nodiscard]] auto disk() const -> int {
    return m_disk;
  }
  [[nodiscard]] auto diskWorstCase() const -> int {
    return m_diskWorstCase;
  }
  [[nodiscard]] auto diskBtrfsAvailable() const -> bool {
    return m_diskBtrfsAvailable;
  }
  [[nodiscard]] auto diskBtrfsFreeEst() const -> double {
    return m_diskBtrfsFreeEst;
  }
  [[nodiscard]] auto diskBtrfsFreeMin() const -> double {
    return m_diskBtrfsFreeMin;
  }
  [[nodiscard]] auto diskHealth() const -> QString {
    return m_diskHealth;
  }
  [[nodiscard]] auto diskWear() const -> QString {
    return m_diskWear;
  }
  [[nodiscard]] auto diskDevice() const -> QString {
    return m_diskDevice;
  }
  [[nodiscard]] auto temp() const -> double {
    return m_temp;
  }
  [[nodiscard]] auto uptime() const -> QString {
    return m_uptime;
  }
  [[nodiscard]] auto psiCpuSome() const -> double {
    return m_psiCpuSome;
  }
  [[nodiscard]] auto psiCpuFull() const -> double {
    return m_psiCpuFull;
  }
  [[nodiscard]] auto psiMemSome() const -> double {
    return m_psiMemSome;
  }
  [[nodiscard]] auto psiMemFull() const -> double {
    return m_psiMemFull;
  }
  [[nodiscard]] auto psiIoSome() const -> double {
    return m_psiIoSome;
  }
  [[nodiscard]] auto psiIoFull() const -> double {
    return m_psiIoFull;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }

  void setDiskDevice(const QString& v);

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void cpuChanged();
  void memChanged();
  void memUsedChanged();
  void memTotalChanged();
  void diskChanged();
  void diskWorstCaseChanged();
  void diskBtrfsAvailableChanged();
  void diskBtrfsFreeEstChanged();
  void diskBtrfsFreeMinChanged();
  void diskHealthChanged();
  void diskWearChanged();
  void diskDeviceChanged();
  void tempChanged();
  void uptimeChanged();
  void psiCpuSomeChanged();
  void psiCpuFullChanged();
  void psiMemSomeChanged();
  void psiMemFullChanged();
  void psiIoSomeChanged();
  void psiIoFullChanged();
  void errorChanged();

private:
  void applySnapshot(double cpu, int mem, const QString& memUsed, const QString& memTotal, int disk,
                     int diskWorstCase, bool diskBtrfsAvailable, double diskBtrfsFreeEst,
                     double diskBtrfsFreeMin, const QString& diskHealth, const QString& diskWear,
                     const QString& diskDevice, double temp, const QString& uptime,
                     double psiCpuSome, double psiCpuFull, double psiMemSome, double psiMemFull,
                     double psiIoSome, double psiIoFull, const QString& error);

  double m_cpu = 0;
  int m_mem = 0;
  QString m_memUsed;
  QString m_memTotal;
  int m_disk = 0;
  int m_diskWorstCase = 0;
  bool m_diskBtrfsAvailable = false;
  double m_diskBtrfsFreeEst = 0;
  double m_diskBtrfsFreeMin = 0;
  QString m_diskHealth;
  QString m_diskWear;
  QString m_diskDevice;
  double m_temp = 0;
  QString m_uptime;
  double m_psiCpuSome = 0;
  double m_psiCpuFull = 0;
  double m_psiMemSome = 0;
  double m_psiMemFull = 0;
  double m_psiIoSome = 0;
  double m_psiIoFull = 0;
  QString m_error;
  double m_lastCpuTotal = 0;
  double m_lastCpuIdle = 0;
  qint64 m_lastDiskHealthMs = 0;
  QString m_diskHealthCache;
  QString m_diskWearCache;
  qint64 m_lastBtrfsMs = 0;
  bool m_btrfsAvailableCache = false;
  int m_btrfsDiskCache = 0;
  double m_btrfsFreeEstCache = 0;
  double m_btrfsFreeMinCache = 0;
  int m_btrfsWorstCaseCache = 0;
};
