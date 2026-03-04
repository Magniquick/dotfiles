#include "QsGoBacklight.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoBacklight::QsGoBacklight(QObject* parent) : QObject(parent) {}

QsGoBacklight::~QsGoBacklight()
{
  stopMonitor();
}

bool QsGoBacklight::refresh()
{
  QThreadPool::globalInstance()->start([this]() {
    char* raw = QsGo_Backlight_Get();
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) return;
      const QJsonObject obj = doc.object();

      const int pct = obj.value(QLatin1String("percent")).toInt();
      if (pct != m_brightnessPercent) {
        m_brightnessPercent = pct;
        emit brightnessPercentChanged();
      }
      const QString dev = obj.value(QLatin1String("device")).toString();
      if (dev != m_device) {
        const bool wasAvailable = !m_device.isEmpty();
        m_device = dev;
        emit deviceChanged();
        if (wasAvailable != !m_device.isEmpty()) emit availableChanged();
      }
      const QString err = obj.value(QLatin1String("error")).toString();
      if (err != m_error) {
        m_error = err;
        emit errorChanged();
      }
    }, Qt::QueuedConnection);
  });
  return true;
}

bool QsGoBacklight::setBrightness(int percent)
{
  const int pct = percent;
  QThreadPool::globalInstance()->start([this, pct]() {
    char* raw = QsGo_Backlight_Set(pct);
    QByteArray json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(this, [this, json]() {
      const QJsonDocument doc = QJsonDocument::fromJson(json);
      if (!doc.isObject()) return;
      const QJsonObject obj = doc.object();

      const int newPct = obj.value(QLatin1String("percent")).toInt();
      if (newPct != m_brightnessPercent) {
        m_brightnessPercent = newPct;
        emit brightnessPercentChanged();
      }
      const QString err = obj.value(QLatin1String("error")).toString();
      if (err != m_error) {
        m_error = err;
        emit errorChanged();
      }
    }, Qt::QueuedConnection);
  });
  return true;
}

void QsGoBacklight::start()
{
  startMonitor();
}

void QsGoBacklight::startMonitor()
{
  if (m_monitorId >= 0) return;
  m_monitorId = QsGo_Backlight_Monitor(&QsGoBacklight::brightCallback, this);
  refresh();
}

void QsGoBacklight::stopMonitor()
{
  if (m_monitorId < 0) return;
  QsGo_Backlight_StopMonitor(m_monitorId);
  m_monitorId = -1;
}

// Static callback — called from a Go goroutine (not the Qt thread).
void QsGoBacklight::brightCallback(void* ctx, int percent, const char* device)
{
  auto* self = static_cast<QsGoBacklight*>(ctx);
  QString dev(device);
  QMetaObject::invokeMethod(self, [self, percent, dev]() {
    if (percent != self->m_brightnessPercent) {
      self->m_brightnessPercent = percent;
      emit self->brightnessPercentChanged();
    }
    if (dev != self->m_device) {
      const bool wasAvailable = !self->m_device.isEmpty();
      self->m_device = dev;
      emit self->deviceChanged();
      if (wasAvailable != !self->m_device.isEmpty()) emit self->availableChanged();
    }
  }, Qt::QueuedConnection);
}
