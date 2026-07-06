#include "QsNativeSysInfo.h"
#include "qsnative_api.h"

#include <QMetaObject>

QsNativeSysInfo::QsNativeSysInfo(QObject* parent)
    : QObject(parent), m_handle(QsNative_SysInfo_New()) {}

QsNativeSysInfo::~QsNativeSysInfo() {
  QsNative_SysInfo_Delete(m_handle);
}

auto QsNativeSysInfo::refresh() -> bool {
  QsNative_SysInfo_Refresh(m_handle, this, &QsNativeSysInfo::snapshotCallback);
  return true;
}

void QsNativeSysInfo::snapshotCallback(void* ctx, const SysInfoSnapshotC* snap) {
  auto* self = static_cast<QsNativeSysInfo*>(ctx);
  if (snap == nullptr) {
    return;
  }

  // Deep-copy synchronously: the char* fields are only valid for this call.
  Snapshot s;
  s.cpu = snap->cpu;
  s.mem = snap->mem;
  s.memUsed = QString::fromUtf8(snap->mem_used);
  s.memTotal = QString::fromUtf8(snap->mem_total);
  s.disk = snap->disk;
  s.diskWorstCase = snap->disk_worst_case;
  s.diskBtrfsAvailable = snap->disk_btrfs_available;
  s.diskBtrfsFreeEstGib = snap->disk_btrfs_free_est_gib;
  s.diskBtrfsFreeMinGib = snap->disk_btrfs_free_min_gib;
  s.diskHealth = QString::fromUtf8(snap->disk_health);
  s.diskWear = QString::fromUtf8(snap->disk_wear);
  s.diskDevice = QString::fromUtf8(snap->disk_device);
  s.temp = snap->temp;
  s.uptime = QString::fromUtf8(snap->uptime);
  s.psiCpuSome = snap->psi_cpu_some;
  s.psiCpuFull = snap->psi_cpu_full;
  s.psiMemSome = snap->psi_mem_some;
  s.psiMemFull = snap->psi_mem_full;
  s.psiIoSome = snap->psi_io_some;
  s.psiIoFull = snap->psi_io_full;
  s.error = QString::fromUtf8(snap->error);

  QMetaObject::invokeMethod(
      self, [self, s]() { self->applySnapshot(s); }, Qt::QueuedConnection);
}

void QsNativeSysInfo::applySnapshot(const Snapshot& snapshot) {
  m_data = snapshot;
  emit changed();
}
