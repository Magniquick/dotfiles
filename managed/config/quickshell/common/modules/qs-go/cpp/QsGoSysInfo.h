#pragma once
#include <QObject>

class QsGoSysInfo : public QObject {
  Q_OBJECT

  Q_PROPERTY(double  cpu                  READ cpu                  NOTIFY cpuChanged)
  Q_PROPERTY(int     mem                  READ mem                  NOTIFY memChanged)
  Q_PROPERTY(QString mem_used             READ memUsed              NOTIFY memUsedChanged)
  Q_PROPERTY(QString mem_total            READ memTotal             NOTIFY memTotalChanged)
  Q_PROPERTY(int     disk                 READ disk                 NOTIFY diskChanged)
  Q_PROPERTY(int     disk_worst_case      READ diskWorstCase        NOTIFY diskWorstCaseChanged)
  Q_PROPERTY(bool    disk_btrfs_available READ diskBtrfsAvailable   NOTIFY diskBtrfsAvailableChanged)
  Q_PROPERTY(double  disk_btrfs_free_est_gib READ diskBtrfsFreeEst NOTIFY diskBtrfsFreeEstChanged)
  Q_PROPERTY(double  disk_btrfs_free_min_gib READ diskBtrfsFreeMin NOTIFY diskBtrfsFreeMinChanged)
  Q_PROPERTY(QString disk_health          READ diskHealth           NOTIFY diskHealthChanged)
  Q_PROPERTY(QString disk_wear            READ diskWear             NOTIFY diskWearChanged)
  Q_PROPERTY(QString disk_device          READ diskDevice           WRITE setDiskDevice NOTIFY diskDeviceChanged)
  Q_PROPERTY(double  temp                 READ temp                 NOTIFY tempChanged)
  Q_PROPERTY(QString uptime               READ uptime               NOTIFY uptimeChanged)
  Q_PROPERTY(double  psi_cpu_some         READ psiCpuSome           NOTIFY psiCpuSomeChanged)
  Q_PROPERTY(double  psi_cpu_full         READ psiCpuFull           NOTIFY psiCpuFullChanged)
  Q_PROPERTY(double  psi_mem_some         READ psiMemSome           NOTIFY psiMemSomeChanged)
  Q_PROPERTY(double  psi_mem_full         READ psiMemFull           NOTIFY psiMemFullChanged)
  Q_PROPERTY(double  psi_io_some          READ psiIoSome            NOTIFY psiIoSomeChanged)
  Q_PROPERTY(double  psi_io_full          READ psiIoFull            NOTIFY psiIoFullChanged)
  Q_PROPERTY(QString error                READ error                NOTIFY errorChanged)

public:
  explicit QsGoSysInfo(QObject* parent = nullptr);

  double  cpu()                const { return m_cpu; }
  int     mem()                const { return m_mem; }
  QString memUsed()            const { return m_memUsed; }
  QString memTotal()           const { return m_memTotal; }
  int     disk()               const { return m_disk; }
  int     diskWorstCase()      const { return m_diskWorstCase; }
  bool    diskBtrfsAvailable() const { return m_diskBtrfsAvailable; }
  double  diskBtrfsFreeEst()   const { return m_diskBtrfsFreeEst; }
  double  diskBtrfsFreeMin()   const { return m_diskBtrfsFreeMin; }
  QString diskHealth()         const { return m_diskHealth; }
  QString diskWear()           const { return m_diskWear; }
  QString diskDevice()         const { return m_diskDevice; }
  double  temp()               const { return m_temp; }
  QString uptime()             const { return m_uptime; }
  double  psiCpuSome()         const { return m_psiCpuSome; }
  double  psiCpuFull()         const { return m_psiCpuFull; }
  double  psiMemSome()         const { return m_psiMemSome; }
  double  psiMemFull()         const { return m_psiMemFull; }
  double  psiIoSome()          const { return m_psiIoSome; }
  double  psiIoFull()          const { return m_psiIoFull; }
  QString error()              const { return m_error; }

  void setDiskDevice(const QString& v);

  Q_INVOKABLE bool refresh();

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
  double  m_cpu = 0;
  int     m_mem = 0;
  QString m_memUsed;
  QString m_memTotal;
  int     m_disk = 0;
  int     m_diskWorstCase = 0;
  bool    m_diskBtrfsAvailable = false;
  double  m_diskBtrfsFreeEst = 0;
  double  m_diskBtrfsFreeMin = 0;
  QString m_diskHealth;
  QString m_diskWear;
  QString m_diskDevice;
  double  m_temp = 0;
  QString m_uptime;
  double  m_psiCpuSome = 0;
  double  m_psiCpuFull = 0;
  double  m_psiMemSome = 0;
  double  m_psiMemFull = 0;
  double  m_psiIoSome = 0;
  double  m_psiIoFull = 0;
  QString m_error;
};
