#pragma once

#include <QObject>
#include <QString>

struct SysInfoHandle;
struct SysInfoSnapshotC;

// System metrics provider. Rust reads /proc, sysfs, smartctl and btrfs ioctls on
// a worker thread and delivers a zero-copy `SysInfoSnapshotC` (a #[repr(C)]
// struct); this QObject copies it on the Qt thread. All properties update
// together, so a single `changed()` signal drives every binding.
class QsNativeSysInfo : public QObject {
  Q_OBJECT

  Q_PROPERTY(double cpu READ cpu NOTIFY changed)
  Q_PROPERTY(int mem READ mem NOTIFY changed)
  Q_PROPERTY(QString mem_used READ memUsed NOTIFY changed)
  Q_PROPERTY(QString mem_total READ memTotal NOTIFY changed)
  Q_PROPERTY(int disk READ disk NOTIFY changed)
  Q_PROPERTY(int disk_worst_case READ diskWorstCase NOTIFY changed)
  Q_PROPERTY(bool disk_btrfs_available READ diskBtrfsAvailable NOTIFY changed)
  Q_PROPERTY(double disk_btrfs_free_est_gib READ diskBtrfsFreeEstGib NOTIFY changed)
  Q_PROPERTY(double disk_btrfs_free_min_gib READ diskBtrfsFreeMinGib NOTIFY changed)
  Q_PROPERTY(QString disk_health READ diskHealth NOTIFY changed)
  Q_PROPERTY(QString disk_wear READ diskWear NOTIFY changed)
  Q_PROPERTY(QString disk_device READ diskDevice NOTIFY changed)
  Q_PROPERTY(double temp READ temp NOTIFY changed)
  Q_PROPERTY(QString uptime READ uptime NOTIFY changed)
  Q_PROPERTY(double psi_cpu_some READ psiCpuSome NOTIFY changed)
  Q_PROPERTY(double psi_cpu_full READ psiCpuFull NOTIFY changed)
  Q_PROPERTY(double psi_mem_some READ psiMemSome NOTIFY changed)
  Q_PROPERTY(double psi_mem_full READ psiMemFull NOTIFY changed)
  Q_PROPERTY(double psi_io_some READ psiIoSome NOTIFY changed)
  Q_PROPERTY(double psi_io_full READ psiIoFull NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)

public:
  explicit QsNativeSysInfo(QObject* parent = nullptr);
  ~QsNativeSysInfo() override;

  [[nodiscard]] auto cpu() const -> double { return m_data.cpu; }
  [[nodiscard]] auto mem() const -> int { return m_data.mem; }
  [[nodiscard]] auto memUsed() const -> QString { return m_data.memUsed; }
  [[nodiscard]] auto memTotal() const -> QString { return m_data.memTotal; }
  [[nodiscard]] auto disk() const -> int { return m_data.disk; }
  [[nodiscard]] auto diskWorstCase() const -> int { return m_data.diskWorstCase; }
  [[nodiscard]] auto diskBtrfsAvailable() const -> bool { return m_data.diskBtrfsAvailable; }
  [[nodiscard]] auto diskBtrfsFreeEstGib() const -> double { return m_data.diskBtrfsFreeEstGib; }
  [[nodiscard]] auto diskBtrfsFreeMinGib() const -> double { return m_data.diskBtrfsFreeMinGib; }
  [[nodiscard]] auto diskHealth() const -> QString { return m_data.diskHealth; }
  [[nodiscard]] auto diskWear() const -> QString { return m_data.diskWear; }
  [[nodiscard]] auto diskDevice() const -> QString { return m_data.diskDevice; }
  [[nodiscard]] auto temp() const -> double { return m_data.temp; }
  [[nodiscard]] auto uptime() const -> QString { return m_data.uptime; }
  [[nodiscard]] auto psiCpuSome() const -> double { return m_data.psiCpuSome; }
  [[nodiscard]] auto psiCpuFull() const -> double { return m_data.psiCpuFull; }
  [[nodiscard]] auto psiMemSome() const -> double { return m_data.psiMemSome; }
  [[nodiscard]] auto psiMemFull() const -> double { return m_data.psiMemFull; }
  [[nodiscard]] auto psiIoSome() const -> double { return m_data.psiIoSome; }
  [[nodiscard]] auto psiIoFull() const -> double { return m_data.psiIoFull; }
  [[nodiscard]] auto error() const -> QString { return m_data.error; }

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void changed();

private:
  // Qt-owned copy of a snapshot (deep-copied off the borrowed SysInfoSnapshotC).
  struct Snapshot {
    double cpu = 0.0;
    int mem = 0;
    QString memUsed;
    QString memTotal;
    int disk = 0;
    int diskWorstCase = 0;
    bool diskBtrfsAvailable = false;
    double diskBtrfsFreeEstGib = 0.0;
    double diskBtrfsFreeMinGib = 0.0;
    QString diskHealth;
    QString diskWear;
    QString diskDevice;
    double temp = 0.0;
    QString uptime;
    double psiCpuSome = 0.0;
    double psiCpuFull = 0.0;
    double psiMemSome = 0.0;
    double psiMemFull = 0.0;
    double psiIoSome = 0.0;
    double psiIoFull = 0.0;
    QString error;
  };

  static void snapshotCallback(void* ctx, const SysInfoSnapshotC* snap);
  void applySnapshot(const Snapshot& snapshot);

  SysInfoHandle* m_handle;
  Snapshot m_data;
};
