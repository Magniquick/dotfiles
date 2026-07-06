#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

struct PrivacyHandle;

// Privacy provider. Rust owns a persistent inotifywait camera watcher plus
// fuser/ps probe workers and delivers typed JSON events; this QObject owns every
// Qt property and all state-transition/logging behaviour on the Qt thread. A
// single `changed()` signal drives every binding. PipeWire mic/screencast
// classification is a synchronous Rust helper.
class QsNativePrivacy : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool microphone_active READ microphoneActive NOTIFY changed)
  Q_PROPERTY(bool camera_active READ cameraActive NOTIFY changed)
  Q_PROPERTY(bool screensharing_active READ screensharingActive NOTIFY changed)
  Q_PROPERTY(bool any_privacy_active READ anyPrivacyActive NOTIFY changed)
  Q_PROPERTY(QString camera_device READ cameraDevice WRITE setCameraDevice NOTIFY changed)
  Q_PROPERTY(bool camera_open_seen READ cameraOpenSeen NOTIFY changed)
  Q_PROPERTY(bool camera_pending_confirmation READ cameraPendingConfirmation NOTIFY changed)
  Q_PROPERTY(bool probing_camera READ probingCamera NOTIFY changed)
  Q_PROPERTY(QString camera_holder_apps READ cameraHolderApps NOTIFY changed)
  Q_PROPERTY(QString camera_holders_summary READ cameraHoldersSummary NOTIFY changed)
  Q_PROPERTY(QString camera_activation_state READ cameraActivationState NOTIFY changed)
  Q_PROPERTY(int camera_retry_attempt READ cameraRetryAttempt NOTIFY changed)
  Q_PROPERTY(bool camera_degraded READ cameraDegraded NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
  Q_PROPERTY(bool debug READ debug WRITE setDebug NOTIFY changed)
  Q_PROPERTY(
      bool privacy_stdout_logging READ privacyStdoutLogging WRITE setPrivacyStdoutLogging NOTIFY
          changed)
  Q_PROPERTY(
      bool privacy_file_logging READ privacyFileLogging WRITE setPrivacyFileLogging NOTIFY changed)
  Q_PROPERTY(QString camera_log_path READ cameraLogPath WRITE setCameraLogPath NOTIFY changed)

public:
  explicit QsNativePrivacy(QObject* parent = nullptr);
  ~QsNativePrivacy() override;

  [[nodiscard]] auto microphoneActive() const -> bool { return m_microphoneActive; }
  [[nodiscard]] auto cameraActive() const -> bool { return m_cameraActive; }
  [[nodiscard]] auto screensharingActive() const -> bool { return m_screensharingActive; }
  [[nodiscard]] auto anyPrivacyActive() const -> bool { return m_anyPrivacyActive; }
  [[nodiscard]] auto cameraDevice() const -> QString { return m_cameraDevice; }
  [[nodiscard]] auto cameraOpenSeen() const -> bool { return m_cameraOpenSeen; }
  [[nodiscard]] auto cameraPendingConfirmation() const -> bool { return m_cameraPendingConfirmation; }
  [[nodiscard]] auto probingCamera() const -> bool { return m_probingCamera; }
  [[nodiscard]] auto cameraHolderApps() const -> QString { return m_cameraHolderApps; }
  [[nodiscard]] auto cameraHoldersSummary() const -> QString { return m_cameraHoldersSummary; }
  [[nodiscard]] auto cameraActivationState() const -> QString { return m_cameraActivationState; }
  [[nodiscard]] auto cameraRetryAttempt() const -> int { return m_cameraRetryAttempt; }
  [[nodiscard]] auto cameraDegraded() const -> bool { return m_cameraDegraded; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto debug() const -> bool { return m_debug; }
  [[nodiscard]] auto privacyStdoutLogging() const -> bool { return m_privacyStdoutLogging; }
  [[nodiscard]] auto privacyFileLogging() const -> bool { return m_privacyFileLogging; }
  [[nodiscard]] auto cameraLogPath() const -> QString { return m_cameraLogPath; }

  void setCameraDevice(const QString& value);
  void setDebug(bool value);
  void setPrivacyStdoutLogging(bool value);
  void setPrivacyFileLogging(bool value);
  void setCameraLogPath(const QString& value);

  Q_INVOKABLE void start();
  Q_INVOKABLE auto refreshCamera() -> bool;
  Q_INVOKABLE auto updatePipewireSnapshot(const QString& snapshotJson) -> bool;

signals:
  void changed();

private:
  static void eventCallback(void* ctx, const char* json);
  void applyEvent(const QString& json);
  void onCameraEvent(bool openSeen);
  void onCameraMonitorExited(const QString& error);
  void applyCameraProbe(const QStringList& hits, const QStringList& apps, bool fromOpen);
  void applyCameraHolderState(const QStringList& hits, const QStringList& apps);
  void refreshAnyPrivacyActive();
  void persistCameraLogLine(const QString& line) const;
  [[nodiscard]] auto buildCameraLogLine(const QStringList& hits, const QStringList& apps) const
      -> QString;

  PrivacyHandle* m_handle;

  bool m_microphoneActive = false;
  bool m_cameraActive = false;
  bool m_screensharingActive = false;
  bool m_anyPrivacyActive = false;
  QString m_cameraDevice = QStringLiteral("/dev/video0");
  bool m_cameraOpenSeen = false;
  bool m_cameraPendingConfirmation = false;
  bool m_probingCamera = false;
  QString m_cameraHolderApps;
  QString m_cameraHoldersSummary;
  QString m_cameraActivationState = QStringLiteral("inactive");
  int m_cameraRetryAttempt = 0;
  bool m_cameraDegraded = false;
  QString m_error;
  bool m_debug = false;
  bool m_privacyStdoutLogging = true;
  bool m_privacyFileLogging = true;
  QString m_cameraLogPath = QStringLiteral("/tmp/quickshell-privacy-camera.log");
  bool m_started = false;
};
