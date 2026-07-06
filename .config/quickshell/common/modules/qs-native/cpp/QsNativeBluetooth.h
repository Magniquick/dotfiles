#pragma once

#include <QObject>
#include <QString>

struct BluetoothHandle;

// Bluetooth discovery diagnostics provider (debug helpers for the Bluetooth bar
// module). Rust runs a system-bus D-Bus monitor and a session-bus tooltip probe
// on worker threads and delivers partial JSON snapshots; this QObject applies
// each present key on the Qt thread, emitting the matching per-property change
// signal. Property names stay snake_case to match the QML `Connections` handlers.
class QsNativeBluetooth : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString last_start_discovery_sender READ lastStartDiscoverySender WRITE
                 setLastStartDiscoverySender NOTIFY last_start_discovery_senderChanged)
  Q_PROPERTY(int last_start_discovery_pid READ lastStartDiscoveryPid WRITE setLastStartDiscoveryPid
                 NOTIFY last_start_discovery_pidChanged)
  Q_PROPERTY(QString last_start_discovery_process READ lastStartDiscoveryProcess WRITE
                 setLastStartDiscoveryProcess NOTIFY last_start_discovery_processChanged)
  Q_PROPERTY(QString last_scan_holders READ lastScanHolders WRITE setLastScanHolders NOTIFY
                 last_scan_holdersChanged)
  Q_PROPERTY(QString librepods_tooltip READ librepodsTooltip WRITE setLibrepodsTooltip NOTIFY
                 librepods_tooltipChanged)
  Q_PROPERTY(QString error READ error WRITE setError NOTIFY errorChanged)
  Q_PROPERTY(bool monitoring READ monitoring WRITE setMonitoring NOTIFY monitoringChanged)

public:
  explicit QsNativeBluetooth(QObject* parent = nullptr);
  ~QsNativeBluetooth() override;

  [[nodiscard]] auto lastStartDiscoverySender() const -> QString {
    return m_lastStartDiscoverySender;
  }
  [[nodiscard]] auto lastStartDiscoveryPid() const -> int {
    return m_lastStartDiscoveryPid;
  }
  [[nodiscard]] auto lastStartDiscoveryProcess() const -> QString {
    return m_lastStartDiscoveryProcess;
  }
  [[nodiscard]] auto lastScanHolders() const -> QString {
    return m_lastScanHolders;
  }
  [[nodiscard]] auto librepodsTooltip() const -> QString {
    return m_librepodsTooltip;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }
  [[nodiscard]] auto monitoring() const -> bool {
    return m_monitoring;
  }

  void setLastStartDiscoverySender(const QString& v);
  void setLastStartDiscoveryPid(int v);
  void setLastStartDiscoveryProcess(const QString& v);
  void setLastScanHolders(const QString& v);
  void setLibrepodsTooltip(const QString& v);
  void setError(const QString& v);
  void setMonitoring(bool v);

  Q_INVOKABLE auto startDiscoveryMonitor() -> bool;
  Q_INVOKABLE void stopDiscoveryMonitor();
  Q_INVOKABLE auto probeScanHolders() -> bool;
  Q_INVOKABLE auto probeLibrepodsTooltip() -> bool;

signals:
  void last_start_discovery_senderChanged();
  void last_start_discovery_pidChanged();
  void last_start_discovery_processChanged();
  void last_scan_holdersChanged();
  void librepods_tooltipChanged();
  void errorChanged();
  void monitoringChanged();

private:
  static void snapshotCallback(void* ctx, const char* json);
  void applySnapshot(const QString& json);

  BluetoothHandle* m_handle;

  QString m_lastStartDiscoverySender;
  int m_lastStartDiscoveryPid = -1;
  QString m_lastStartDiscoveryProcess;
  QString m_lastScanHolders;
  QString m_librepodsTooltip;
  QString m_error;
  bool m_monitoring = false;
};
