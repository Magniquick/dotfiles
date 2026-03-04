#pragma once
#include <QObject>

class QsGoBacklight : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool    available          READ available          NOTIFY availableChanged)
  Q_PROPERTY(int     brightness_percent READ brightnessPercent NOTIFY brightnessPercentChanged)
  Q_PROPERTY(QString device             READ device             NOTIFY deviceChanged)
  Q_PROPERTY(QString error              READ error              NOTIFY errorChanged)

public:
  explicit QsGoBacklight(QObject* parent = nullptr);
  ~QsGoBacklight() override;

  bool    available()          const { return !m_device.isEmpty(); }
  int     brightnessPercent() const { return m_brightnessPercent; }
  QString device()             const { return m_device; }
  QString error()              const { return m_error; }

  Q_INVOKABLE bool setBrightness(int percent);

  // Start/stop the udev monitor.
  Q_INVOKABLE void start();
  Q_INVOKABLE void startMonitor();
  Q_INVOKABLE void stopMonitor();

  // Read current value without starting the monitor.
  Q_INVOKABLE bool refresh();

signals:
  void availableChanged();
  void brightnessPercentChanged();
  void deviceChanged();
  void errorChanged();

private:
  static void brightCallback(void* ctx, int percent, const char* device);

  int     m_brightnessPercent = 0;
  QString m_device;
  QString m_error;
  int     m_monitorId = -1;
};
