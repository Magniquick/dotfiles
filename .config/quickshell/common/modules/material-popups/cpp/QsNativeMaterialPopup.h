#pragma once

#include <QObject>
#include <QString>

struct MaterialPopupHandle;

// Clipboard + input-watcher backend. Rust runs a wlr clipboard paste-stream
// watcher and a /dev/input evdev monitor on worker threads and delivers events
// (new clipboard text, keyboard/pointer activity, worker errors) through a
// borrowed-JSON callback; this QObject applies them on the Qt thread. QML polls
// the serial counters rather than connecting to signals, but each property keeps
// its own change notifier for the binding contract.
class QsNativeMaterialPopup : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool running READ running NOTIFY runningChanged)
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString lastText READ lastText NOTIFY lastTextChanged)
  Q_PROPERTY(int copySerial READ copySerial NOTIFY copySerialChanged)
  Q_PROPERTY(QString activityKind READ activityKind NOTIFY activityKindChanged)
  Q_PROPERTY(int activitySerial READ activitySerial NOTIFY activitySerialChanged)

public:
  explicit QsNativeMaterialPopup(QObject* parent = nullptr);
  ~QsNativeMaterialPopup() override;

  [[nodiscard]] auto running() const -> bool { return m_running; }
  [[nodiscard]] auto available() const -> bool { return m_available; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto lastText() const -> QString { return m_lastText; }
  [[nodiscard]] auto copySerial() const -> int { return m_copySerial; }
  [[nodiscard]] auto activityKind() const -> QString { return m_activityKind; }
  [[nodiscard]] auto activitySerial() const -> int { return m_activitySerial; }

  Q_INVOKABLE void start();
  Q_INVOKABLE void stop();

signals:
  void runningChanged();
  void availableChanged();
  void errorChanged();
  void lastTextChanged();
  void copySerialChanged();
  void activityKindChanged();
  void activitySerialChanged();

private:
  static void updateCallback(void* ctx, const char* json);
  void applyEvent(const QString& json);

  void setRunning(bool value);
  void setAvailable(bool value);
  void setError(const QString& value);
  void publishClipboard(const QString& text);
  void publishActivity(const QString& kind);
  void publishError(const QString& message);

  MaterialPopupHandle* m_handle;

  bool m_running = false;
  bool m_available = false;
  QString m_error;
  QString m_lastText;
  int m_copySerial = 0;
  QString m_activityKind;
  int m_activitySerial = 0;
};
