#pragma once
#include <QFileSystemWatcher>
#include <QObject>

class QsGoBacklight : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(int brightness_percent READ brightnessPercent NOTIFY brightnessPercentChanged)
  Q_PROPERTY(QString device READ device NOTIFY deviceChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  explicit QsGoBacklight(QObject* parent = nullptr);
  ~QsGoBacklight() override;

  [[nodiscard]] auto available() const -> bool {
    return !m_device.isEmpty();
  }
  [[nodiscard]] auto brightnessPercent() const -> int {
    return m_brightnessPercent;
  }
  [[nodiscard]] auto device() const -> QString {
    return m_device;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }

  Q_INVOKABLE auto setBrightness(int percent) -> bool;

  // Start/stop the udev monitor.
  Q_INVOKABLE void start();
  Q_INVOKABLE void startMonitor();
  Q_INVOKABLE void stopMonitor();

  // Read current value without starting the monitor.
  Q_INVOKABLE auto refresh() -> bool;

signals:
  void availableChanged();
  void brightnessPercentChanged();
  void deviceChanged();
  void errorChanged();

private:
  void applyState(int percent, const QString& device, const QString& error);
  [[nodiscard]] static auto deviceDirectory() -> QString;
  [[nodiscard]] static auto brightnessPath() -> QString;
  void ensureWatcher();
  void clearWatcher();

  int m_brightnessPercent = 0;
  QString m_device;
  QString m_error;
  QFileSystemWatcher* m_watcher = nullptr;
};
