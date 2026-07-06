#include "QsNativeMaterialPopup.h"
#include "material_popups_api.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>

namespace {

// Wrapping i32 increment matching the Rust `wrapping_add(1)` semantics without
// relying on signed-overflow behaviour.
[[nodiscard]] auto wrappingInc(int value) -> int {
  return static_cast<int>(static_cast<unsigned int>(value) + 1U);
}

} // namespace

QsNativeMaterialPopup::QsNativeMaterialPopup(QObject* parent)
    : QObject(parent),
      m_handle(QsNative_MaterialPopup_New(this, &QsNativeMaterialPopup::updateCallback)) {}

QsNativeMaterialPopup::~QsNativeMaterialPopup() {
  // Delete disables event delivery (blocking any in-flight worker) before the
  // QObject is torn down, so no callback can reach a destroyed receiver.
  QsNative_MaterialPopup_Delete(m_handle);
}

void QsNativeMaterialPopup::start() {
  if (m_running) {
    return;
  }
  setRunning(true);
  setAvailable(true);
  setError(QString());
  QsNative_MaterialPopup_Start(m_handle);
}

void QsNativeMaterialPopup::stop() {
  QsNative_MaterialPopup_Stop(m_handle);
  setRunning(false);
}

void QsNativeMaterialPopup::updateCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativeMaterialPopup*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  QMetaObject::invokeMethod(
      self, [self, payload]() { self->applyEvent(payload); }, Qt::QueuedConnection);
}

void QsNativeMaterialPopup::applyEvent(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    return;
  }
  const QJsonObject o = doc.object();
  const QString kind = o.value(QStringLiteral("kind")).toString();

  if (kind == QStringLiteral("clipboard")) {
    publishClipboard(o.value(QStringLiteral("text")).toString());
  } else if (kind == QStringLiteral("activity")) {
    publishActivity(o.value(QStringLiteral("activity")).toString());
  } else if (kind == QStringLiteral("error")) {
    publishError(o.value(QStringLiteral("error")).toString());
  }
}

void QsNativeMaterialPopup::setRunning(bool value) {
  if (value != m_running) {
    m_running = value;
    emit runningChanged();
  }
}

void QsNativeMaterialPopup::setAvailable(bool value) {
  if (value != m_available) {
    m_available = value;
    emit availableChanged();
  }
}

void QsNativeMaterialPopup::setError(const QString& value) {
  if (value != m_error) {
    m_error = value;
    emit errorChanged();
  }
}

void QsNativeMaterialPopup::publishClipboard(const QString& text) {
  m_lastText = text;
  emit lastTextChanged();
  m_copySerial = wrappingInc(m_copySerial);
  emit copySerialChanged();
}

void QsNativeMaterialPopup::publishActivity(const QString& kind) {
  m_activityKind = kind;
  emit activityKindChanged();
  m_activitySerial = wrappingInc(m_activitySerial);
  emit activitySerialChanged();
}

void QsNativeMaterialPopup::publishError(const QString& message) {
  setError(message);
  setAvailable(false);
}
