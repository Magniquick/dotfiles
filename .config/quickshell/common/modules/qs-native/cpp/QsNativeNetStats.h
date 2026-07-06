#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>

struct NetStatsHandle;

// Network statistics provider. Everything runs synchronously on the Qt/main
// thread: `refresh()` reads /proc/net/dev and `ethernetMetadataJson()` shells out
// to udevadm. The Rust opaque handle owns the traffic history/smoothing state and
// the source-switch bookkeeping; stateful invokables return a JSON snapshot that
// this QObject mirrors into its properties (each with its own NOTIFY signal so the
// re-exposed readonly bindings in NetworkService.qml update).
class QsNativeNetStats : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString device READ device WRITE setDevice NOTIFY deviceChanged)
  Q_PROPERTY(double rx_bytes READ rxBytes NOTIFY rx_bytesChanged)
  Q_PROPERTY(double tx_bytes READ txBytes NOTIFY tx_bytesChanged)
  Q_PROPERTY(double rxBytesPerSec READ rxBytesPerSec NOTIFY rxBytesPerSecChanged)
  Q_PROPERTY(double txBytesPerSec READ txBytesPerSec NOTIFY txBytesPerSecChanged)
  Q_PROPERTY(QString rxHistoryJson READ rxHistoryJson NOTIFY rxHistoryJsonChanged)
  Q_PROPERTY(QString txHistoryJson READ txHistoryJson NOTIFY txHistoryJsonChanged)
  Q_PROPERTY(double trafficScaleMax READ trafficScaleMax NOTIFY trafficScaleMaxChanged)
  Q_PROPERTY(QString sourceEntriesJson READ sourceEntriesJson NOTIFY sourceEntriesJsonChanged)
  Q_PROPERTY(bool sourceSwitching READ sourceSwitching NOTIFY sourceSwitchingChanged)
  Q_PROPERTY(
      QString sourceSwitchingName READ sourceSwitchingName NOTIFY sourceSwitchingNameChanged)
  Q_PROPERTY(QString sourceError READ sourceError NOTIFY sourceErrorChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsNativeNetStats(QObject* parent = nullptr);
  ~QsNativeNetStats() override;

  [[nodiscard]] auto device() const -> QString { return m_device; }
  [[nodiscard]] auto rxBytes() const -> double { return m_rxBytes; }
  [[nodiscard]] auto txBytes() const -> double { return m_txBytes; }
  [[nodiscard]] auto rxBytesPerSec() const -> double { return m_rxBytesPerSec; }
  [[nodiscard]] auto txBytesPerSec() const -> double { return m_txBytesPerSec; }
  [[nodiscard]] auto rxHistoryJson() const -> QString { return m_rxHistoryJson; }
  [[nodiscard]] auto txHistoryJson() const -> QString { return m_txHistoryJson; }
  [[nodiscard]] auto trafficScaleMax() const -> double { return m_trafficScaleMax; }
  [[nodiscard]] auto sourceEntriesJson() const -> QString { return m_sourceEntriesJson; }
  [[nodiscard]] auto sourceSwitching() const -> bool { return m_sourceSwitching; }
  [[nodiscard]] auto sourceSwitchingName() const -> QString { return m_sourceSwitchingName; }
  [[nodiscard]] auto sourceError() const -> QString { return m_sourceError; }
  [[nodiscard]] auto error() const -> QString { return m_error; }

  void setDevice(const QString& device);

  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE void updateTrafficRates(double rx_bytes, double tx_bytes, double now_ms);
  Q_INVOKABLE void resetTraffic();
  Q_INVOKABLE auto setSourceEntries(const QString& entries_json) -> bool;
  Q_INVOKABLE auto beginSourceSwitch(const QString& name) -> bool;
  Q_INVOKABLE void failSourceSwitch(const QString& message);
  Q_INVOKABLE void clearSourceSwitch();
  Q_INVOKABLE [[nodiscard]] auto parseIpAddressJson(const QString& text) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto parseGatewayJson(const QString& text) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto normalizeEthernetLabel(const QString& text) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto ethernetMetadataJson(const QString& device_name) const -> QString;

signals:
  void sampleReady(double rx_bytes, double tx_bytes);

  void deviceChanged();
  void rx_bytesChanged();
  void tx_bytesChanged();
  void rxBytesPerSecChanged();
  void txBytesPerSecChanged();
  void rxHistoryJsonChanged();
  void txHistoryJsonChanged();
  void trafficScaleMaxChanged();
  void sourceEntriesJsonChanged();
  void sourceSwitchingChanged();
  void sourceSwitchingNameChanged();
  void sourceErrorChanged();
  void errorChanged();

private:
  void applyTrafficSnapshot(const QVariantMap& o);
  void applySourceSnapshot(const QVariantMap& o);

  void setRxBytes(double v);
  void setTxBytes(double v);
  void setRxBytesPerSec(double v);
  void setTxBytesPerSec(double v);
  void setRxHistoryJson(const QString& v);
  void setTxHistoryJson(const QString& v);
  void setTrafficScaleMax(double v);
  void setSourceEntriesJson(const QString& v);
  void setSourceSwitching(bool v);
  void setSourceSwitchingName(const QString& v);
  void setSourceError(const QString& v);
  void setError(const QString& v);

  NetStatsHandle* m_handle;

  QString m_device;
  double m_rxBytes = 0.0;
  double m_txBytes = 0.0;
  double m_rxBytesPerSec = 0.0;
  double m_txBytesPerSec = 0.0;
  QString m_rxHistoryJson = QStringLiteral("[]");
  QString m_txHistoryJson = QStringLiteral("[]");
  double m_trafficScaleMax = 1024.0;
  QString m_sourceEntriesJson = QStringLiteral("[]");
  bool m_sourceSwitching = false;
  QString m_sourceSwitchingName;
  QString m_sourceError;
  QString m_error;
};
