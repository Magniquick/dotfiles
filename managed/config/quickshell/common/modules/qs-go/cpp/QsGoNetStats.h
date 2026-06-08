#pragma once

#include <QObject>
#include <QString>

class QsGoNetStats : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString device READ device WRITE setDevice NOTIFY deviceChanged)
  Q_PROPERTY(double rx_bytes READ rxBytes NOTIFY rxBytesChanged)
  Q_PROPERTY(double tx_bytes READ txBytes NOTIFY txBytesChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsGoNetStats(QObject* parent = nullptr);

  [[nodiscard]] auto device() const -> QString {
    return m_device;
  }
  [[nodiscard]] auto rxBytes() const -> double {
    return m_rxBytes;
  }
  [[nodiscard]] auto txBytes() const -> double {
    return m_txBytes;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }

  void setDevice(const QString& value);

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void deviceChanged();
  void rxBytesChanged();
  void txBytesChanged();
  void errorChanged();
  void sampleReady(double rxBytes, double txBytes);

private:
  void applySnapshot(const QByteArray& json);

  QString m_device;
  double m_rxBytes = 0;
  double m_txBytes = 0;
  QString m_error;
};
