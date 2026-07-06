#include "QsNativeBacklight.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

QsNativeBacklight::QsNativeBacklight(QObject* parent)
    : QObject(parent), m_handle(QsNative_Backlight_New()) {
  // Prime `ddcutil_available` before `start()` — QML reads it without priming.
  m_ddcutilAvailable = QsNative_Backlight_DdcutilAvailable();
}

QsNativeBacklight::~QsNativeBacklight() {
  QsNative_Backlight_Delete(m_handle);
}

void QsNativeBacklight::start() {
  startMonitor();
  refreshDdc();
}

void QsNativeBacklight::startMonitor() {
  refresh();
  const QString error = qsn::takeString(
      QsNative_Backlight_StartMonitor(m_handle, this, &QsNativeBacklight::stateCallback));
  if (!error.isEmpty()) {
    setError(error);
  }
}

void QsNativeBacklight::stopMonitor() {
  QsNative_Backlight_StopMonitor(m_handle);
}

auto QsNativeBacklight::refresh() -> bool {
  QsNative_Backlight_Refresh(this, &QsNativeBacklight::stateCallback);
  return true;
}

auto QsNativeBacklight::setBrightness(int percent) -> bool {
  QsNative_Backlight_SetBrightness(percent, this, &QsNativeBacklight::stateCallback);
  return true;
}

auto QsNativeBacklight::refreshDdc() -> bool {
  const bool available =
      QsNative_Backlight_RefreshDdc(m_handle, this, &QsNativeBacklight::ddcCallback);
  setDdcutilAvailable(available);
  if (!available) {
    // Rust cleared the DDC map synchronously; the async bump only fires when
    // `ddcutil` is present, so tick the version here.
    bumpDdcVersion();
  }
  return true;
}

auto QsNativeBacklight::ddcBusForConnector(const QString& connector) const -> QString {
  const QByteArray key = connector.toUtf8();
  return qsn::takeString(QsNative_Backlight_DdcBusForConnector(m_handle, key.constData()));
}

auto QsNativeBacklight::ddcBrightnessPercent(const QString& connector) const -> int {
  const QByteArray key = connector.toUtf8();
  return QsNative_Backlight_DdcBrightnessPercent(m_handle, key.constData());
}

auto QsNativeBacklight::ddcMaxBrightness(const QString& connector) const -> int {
  const QByteArray key = connector.toUtf8();
  return QsNative_Backlight_DdcMaxBrightness(m_handle, key.constData());
}

auto QsNativeBacklight::ddcError(const QString& connector) const -> QString {
  const QByteArray key = connector.toUtf8();
  return qsn::takeString(QsNative_Backlight_DdcError(m_handle, key.constData()));
}

auto QsNativeBacklight::refreshDdcBrightness(const QString& connector) -> bool {
  const QByteArray key = connector.toUtf8();
  return QsNative_Backlight_RefreshDdcBrightness(m_handle, key.constData(), this,
                                                 &QsNativeBacklight::ddcCallback);
}

auto QsNativeBacklight::setDdcBrightness(const QString& connector, int percent) -> bool {
  const QByteArray key = connector.toUtf8();
  return QsNative_Backlight_SetDdcBrightness(m_handle, key.constData(), percent, this,
                                             &QsNativeBacklight::ddcCallback);
}

void QsNativeBacklight::stateCallback(void* ctx, const BacklightSnapshotC* snap) {
  auto* self = static_cast<QsNativeBacklight*>(ctx);
  if (snap == nullptr) {
    return;
  }

  // Deep-copy synchronously: the char* fields are only valid for this call.
  Snapshot s;
  s.available = snap->available;
  s.brightnessPercent = snap->brightness_percent;
  s.device = QString::fromUtf8(snap->device);
  s.error = QString::fromUtf8(snap->error);

  qsn::postToObject(self, [self, s]() { self->applySnapshot(s); });
}

void QsNativeBacklight::ddcCallback(void* ctx, const char* /*json*/) {
  auto* self = static_cast<QsNativeBacklight*>(ctx);
  qsn::postToObject(self, [self]() { self->bumpDdcVersion(); });
}

void QsNativeBacklight::applySnapshot(const Snapshot& snapshot) {
  setAvailable(snapshot.available);
  setBrightnessPercent(snapshot.brightnessPercent);
  setDevice(snapshot.device);
  setError(snapshot.error);
}

void QsNativeBacklight::setAvailable(bool value) {
  if (m_available == value) {
    return;
  }
  m_available = value;
  emit availableChanged();
}

void QsNativeBacklight::setBrightnessPercent(int value) {
  if (m_brightnessPercent == value) {
    return;
  }
  m_brightnessPercent = value;
  emit brightness_percentChanged();
}

void QsNativeBacklight::setDevice(const QString& value) {
  if (m_device == value) {
    return;
  }
  m_device = value;
  emit deviceChanged();
}

void QsNativeBacklight::setError(const QString& value) {
  if (m_error == value) {
    return;
  }
  m_error = value;
  emit errorChanged();
}

void QsNativeBacklight::setDdcutilAvailable(bool value) {
  if (m_ddcutilAvailable == value) {
    return;
  }
  m_ddcutilAvailable = value;
  emit ddcutil_availableChanged();
}

void QsNativeBacklight::bumpDdcVersion() {
  m_ddcVersion += 1;
  emit ddc_versionChanged();
}
