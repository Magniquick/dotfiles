#include "QsNativePrivacy.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

#include <cstdio>

namespace {

constexpr int kCameraRetryAttempts = 3;

auto toStringList(const QJsonArray& array) -> QStringList {
  QStringList out;
  out.reserve(static_cast<qsizetype>(array.size()));
  for (const QJsonValue& value : array) {
    out.append(value.toString());
  }
  return out;
}

} // namespace

QsNativePrivacy::QsNativePrivacy(QObject* parent)
    : QObject(parent), m_handle(QsNative_Privacy_New()) {}

QsNativePrivacy::~QsNativePrivacy() {
  QsNative_Privacy_Delete(m_handle);
}

// ── Property setters (QML-writable) ───────────────────────────────────────────

void QsNativePrivacy::setCameraDevice(const QString& value) {
  if (value != m_cameraDevice) {
    m_cameraDevice = value;
    emit changed();
  }
}

void QsNativePrivacy::setDebug(bool value) {
  if (value != m_debug) {
    m_debug = value;
    emit changed();
  }
}

void QsNativePrivacy::setPrivacyStdoutLogging(bool value) {
  if (value != m_privacyStdoutLogging) {
    m_privacyStdoutLogging = value;
    emit changed();
  }
}

void QsNativePrivacy::setPrivacyFileLogging(bool value) {
  if (value != m_privacyFileLogging) {
    m_privacyFileLogging = value;
    emit changed();
  }
}

void QsNativePrivacy::setCameraLogPath(const QString& value) {
  if (value != m_cameraLogPath) {
    m_cameraLogPath = value;
    emit changed();
  }
}

// ── Invokables ────────────────────────────────────────────────────────────────

void QsNativePrivacy::start() {
  if (m_started) {
    refreshCamera();
    return;
  }
  m_started = true;
  QsNative_Privacy_StartWatch(m_handle, this, &QsNativePrivacy::eventCallback,
                              m_cameraDevice.toUtf8().constData());
  refreshCamera();
}

auto QsNativePrivacy::refreshCamera() -> bool {
  m_cameraPendingConfirmation = true;
  m_probingCamera = true;
  m_cameraActivationState = QStringLiteral("pending");
  emit changed();
  QsNative_Privacy_Probe(m_handle, this, &QsNativePrivacy::eventCallback,
                         m_cameraDevice.toUtf8().constData(), /*from_open=*/true, m_debug);
  return true;
}

auto QsNativePrivacy::updatePipewireSnapshot(const QString& snapshotJson) -> bool {
  const QJsonDocument doc =
      qsn::takeDoc(QsNative_Privacy_ClassifyPipewire(snapshotJson.toUtf8().constData()));
  const QJsonObject object = doc.object();
  if (!object.value(QStringLiteral("ok")).toBool()) {
    m_error = object.value(QStringLiteral("error")).toString();
    emit changed();
    return false;
  }

  m_microphoneActive = object.value(QStringLiteral("microphone_active")).toBool();
  m_screensharingActive = object.value(QStringLiteral("screensharing_active")).toBool();
  m_error.clear();
  refreshAnyPrivacyActive();
  emit changed();
  return true;
}

// ── Worker-event marshaling (worker thread → queued to Qt thread) ─────────────

void QsNativePrivacy::eventCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativePrivacy*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applyEvent(payload); });
}

void QsNativePrivacy::applyEvent(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    return;
  }
  const QJsonObject object = doc.object();
  const QString type = object.value(QStringLiteral("type")).toString();

  if (type == QStringLiteral("probe")) {
    const QStringList hits = toStringList(object.value(QStringLiteral("hits")).toArray());
    const QStringList apps = toStringList(object.value(QStringLiteral("apps")).toArray());
    applyCameraProbe(hits, apps, object.value(QStringLiteral("from_open")).toBool());
  } else if (type == QStringLiteral("camera_event")) {
    onCameraEvent(object.value(QStringLiteral("open_seen")).toBool());
  } else if (type == QStringLiteral("monitor_exited")) {
    onCameraMonitorExited(object.value(QStringLiteral("error")).toString());
  }
}

// ── State transitions ─────────────────────────────────────────────────────────

void QsNativePrivacy::onCameraEvent(bool openSeen) {
  m_cameraDegraded = false;
  m_cameraOpenSeen = openSeen;
  m_cameraPendingConfirmation = openSeen;
  m_cameraRetryAttempt = 0;
  m_probingCamera = true;
  m_cameraActivationState = QStringLiteral("pending");
  emit changed();

  QsNative_Privacy_Probe(m_handle, this, &QsNativePrivacy::eventCallback,
                         m_cameraDevice.toUtf8().constData(), openSeen, m_debug);
}

void QsNativePrivacy::onCameraMonitorExited(const QString& error) {
  m_cameraDegraded = true;
  m_cameraOpenSeen = false;
  m_cameraPendingConfirmation = false;
  m_probingCamera = false;
  m_cameraRetryAttempt = 0;
  m_error = error;
  applyCameraHolderState({}, {});
}

void QsNativePrivacy::applyCameraProbe(const QStringList& hits, const QStringList& apps,
                                       bool fromOpen) {
  m_cameraRetryAttempt = (fromOpen && hits.isEmpty()) ? kCameraRetryAttempts : 0;
  m_probingCamera = false;
  m_cameraPendingConfirmation = false;
  applyCameraHolderState(hits, apps);
}

void QsNativePrivacy::applyCameraHolderState(const QStringList& hits, const QStringList& apps) {
  const bool wasActive = m_cameraActive;
  const bool cameraActive = !apps.isEmpty();
  const QString activation =
      cameraActive
          ? QStringLiteral("confirmed")
          : ((m_cameraPendingConfirmation || m_probingCamera) ? QStringLiteral("pending")
                                                              : QStringLiteral("inactive"));

  m_cameraHolderApps = apps.join(QStringLiteral(", "));
  m_cameraHoldersSummary = hits.join(QStringLiteral(","));
  m_cameraActive = cameraActive;
  m_cameraActivationState = activation;
  refreshAnyPrivacyActive();
  emit changed();

  if (wasActive != cameraActive) {
    persistCameraLogLine(buildCameraLogLine(hits, apps));
  }
}

void QsNativePrivacy::refreshAnyPrivacyActive() {
  m_anyPrivacyActive = m_microphoneActive || m_cameraActive || m_screensharingActive;
}

// ── Logging ───────────────────────────────────────────────────────────────────

auto QsNativePrivacy::buildCameraLogLine(const QStringList& hits, const QStringList& apps) const
    -> QString {
  const QString holders = hits.isEmpty() ? QStringLiteral("none") : hits.join(QStringLiteral(","));
  const QString appsSuffix =
      apps.isEmpty() ? QString()
                     : QStringLiteral(" camera_apps=%1").arg(apps.join(QStringLiteral(", ")));

  return QStringLiteral("[PrivacyService][%1] camera %2; device=%3 open_seen=%4 activation=%5 "
                        "holder_count=%6 holders=%7%8")
      .arg(QDateTime::currentDateTime().toString(Qt::ISODateWithMs),
           m_cameraActive ? QStringLiteral("ACTIVE") : QStringLiteral("INACTIVE"), m_cameraDevice,
           m_cameraOpenSeen ? QStringLiteral("yes") : QStringLiteral("no"), m_cameraActivationState)
      .arg(apps.size())
      .arg(holders, appsSuffix);
}

void QsNativePrivacy::persistCameraLogLine(const QString& line) const {
  if (m_privacyStdoutLogging) {
    std::fputs(line.toUtf8().constData(), stdout);
    std::fputc('\n', stdout);
  }
  if (!m_privacyFileLogging) {
    return;
  }

  const QString path = m_cameraLogPath.trimmed();
  if (path.isEmpty()) {
    return;
  }

  QFile file(path);
  if (file.open(QIODevice::Append | QIODevice::Text)) {
    QTextStream stream(&file);
    stream << line << '\n';
  }
}
