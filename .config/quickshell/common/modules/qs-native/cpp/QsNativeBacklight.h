#pragma once

#include <QObject>
#include <QString>

struct BacklightHandle;
struct BacklightSnapshotC;

// Backlight provider. Rust watches the sysfs `.../brightness` file and shells out
// to `ddcutil` on worker threads; this QObject applies scalar state on the Qt
// thread and exposes per-connector DDC queries. Scalar backlight state
// (available/brightness/device/error) arrives as a zero-copy `BacklightSnapshotC`
// (a #[repr(C)] struct) and each field notifies individually; the DDC map lives
// in Rust and is re-queried whenever `ddc_version` ticks.
class QsNativeBacklight : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(int brightness_percent READ brightnessPercent NOTIFY brightness_percentChanged)
  Q_PROPERTY(QString device READ device NOTIFY deviceChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(bool ddcutil_available READ ddcutilAvailable NOTIFY ddcutil_availableChanged)
  Q_PROPERTY(int ddc_version READ ddcVersion NOTIFY ddc_versionChanged)

public:
  explicit QsNativeBacklight(QObject* parent = nullptr);
  ~QsNativeBacklight() override;

  [[nodiscard]] auto available() const -> bool { return m_available; }
  [[nodiscard]] auto brightnessPercent() const -> int { return m_brightnessPercent; }
  [[nodiscard]] auto device() const -> QString { return m_device; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto ddcutilAvailable() const -> bool { return m_ddcutilAvailable; }
  [[nodiscard]] auto ddcVersion() const -> int { return m_ddcVersion; }

  Q_INVOKABLE void start();
  Q_INVOKABLE void startMonitor();
  Q_INVOKABLE void stopMonitor();
  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE auto setBrightness(int percent) -> bool;
  Q_INVOKABLE auto refreshDdc() -> bool;
  Q_INVOKABLE [[nodiscard]] auto ddcBusForConnector(const QString& connector) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto ddcBrightnessPercent(const QString& connector) const -> int;
  Q_INVOKABLE [[nodiscard]] auto ddcMaxBrightness(const QString& connector) const -> int;
  Q_INVOKABLE [[nodiscard]] auto ddcError(const QString& connector) const -> QString;
  Q_INVOKABLE auto refreshDdcBrightness(const QString& connector) -> bool;
  Q_INVOKABLE auto setDdcBrightness(const QString& connector, int percent) -> bool;

signals:
  void availableChanged();
  void brightness_percentChanged();
  void deviceChanged();
  void errorChanged();
  void ddcutil_availableChanged();
  void ddc_versionChanged();

private:
  // Qt-owned copy of the scalar snapshot (deep-copied off a borrowed
  // BacklightSnapshotC before the pointers go out of scope).
  struct Snapshot {
    bool available = false;
    int brightnessPercent = 0;
    QString device;
    QString error;
  };

  static void stateCallback(void* ctx, const BacklightSnapshotC* snap);
  static void ddcCallback(void* ctx, const char* json);
  void applySnapshot(const Snapshot& snapshot);

  void setAvailable(bool value);
  void setBrightnessPercent(int value);
  void setDevice(const QString& value);
  void setError(const QString& value);
  void setDdcutilAvailable(bool value);
  void bumpDdcVersion();

  BacklightHandle* m_handle;

  bool m_available = false;
  int m_brightnessPercent = 0;
  QString m_device;
  QString m_error;
  bool m_ddcutilAvailable = false;
  int m_ddcVersion = 0;
};
