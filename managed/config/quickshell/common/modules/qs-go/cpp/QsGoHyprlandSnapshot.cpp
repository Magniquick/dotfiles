#include "QsGoHyprlandSnapshot.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalSocket>
#include <QMetaObject>
#include <QThreadPool>
#include <QTimer>
#include <QSet>

#include <unistd.h>

namespace {

bool isRelevantEvent(const QString& name) {
  static const QSet<QString> kEvents = {
      QStringLiteral("openwindow"),
      QStringLiteral("closewindow"),
      QStringLiteral("movewindow"),
      QStringLiteral("movewindowv2"),
      QStringLiteral("windowtitle"),
      QStringLiteral("windowtitlev2"),
      QStringLiteral("workspace"),
      QStringLiteral("workspacev2"),
      QStringLiteral("focusedmon"),
      QStringLiteral("focusedmonv2"),
      QStringLiteral("changefloatingmode"),
      QStringLiteral("fullscreen"),
      QStringLiteral("pin"),
  };
  return kEvents.contains(name);
}

} // namespace

QsGoHyprlandSnapshot::QsGoHyprlandSnapshot(QObject* parent) : QObject(parent) {}

QsGoHyprlandSnapshot::~QsGoHyprlandSnapshot() {
  stop();
}

QString QsGoHyprlandSnapshot::socketBase() const {
  const QString signature = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
  if (signature.isEmpty())
    return {};

  QString runtimeDir = qEnvironmentVariable("XDG_RUNTIME_DIR");
  if (runtimeDir.isEmpty())
    runtimeDir = QStringLiteral("/run/user/%1").arg(::getuid());
  return runtimeDir + QStringLiteral("/hypr/") + signature;
}

QString QsGoHyprlandSnapshot::readCommand(const QString& command) const {
  const QString path = socketBase() + QStringLiteral("/.socket.sock");
  if (path.isEmpty())
    return {};

  QLocalSocket socket;
  socket.connectToServer(path);
  if (!socket.waitForConnected(2000))
    return {};

  socket.write(command.toUtf8());
  if (!socket.waitForBytesWritten(2000)) {
    socket.abort();
    return {};
  }

  QByteArray data;
  if (socket.waitForReadyRead(2000))
    data += socket.readAll();
  while (socket.waitForReadyRead(20))
    data += socket.readAll();

  socket.disconnectFromServer();
  return QString::fromUtf8(data).trimmed();
}

QsGoHyprlandSnapshot::SnapshotPayload QsGoHyprlandSnapshot::fetchSnapshot() const {
  SnapshotPayload payload;

  const QString activeWorkspaceJson = readCommand(QStringLiteral("j/activeworkspace"));
  if (activeWorkspaceJson.isEmpty()) {
    payload.error = QStringLiteral("failed to read Hyprland active workspace");
    return payload;
  }

  const QString clientsJson = readCommand(QStringLiteral("j/clients"));
  if (clientsJson.isEmpty()) {
    payload.error = QStringLiteral("failed to read Hyprland clients");
    return payload;
  }

  const QJsonDocument workspaceDoc = QJsonDocument::fromJson(activeWorkspaceJson.toUtf8());
  const QJsonDocument clientsDoc = QJsonDocument::fromJson(clientsJson.toUtf8());
  if (!workspaceDoc.isObject() || !clientsDoc.isArray()) {
    payload.error = QStringLiteral("invalid Hyprland IPC JSON");
    return payload;
  }

  payload.activeWorkspace = workspaceDoc.object().toVariantMap();
  payload.clients = clientsDoc.array().toVariantList();
  payload.valid = true;
  return payload;
}

void QsGoHyprlandSnapshot::start() {
  if (m_running) {
    refresh();
    return;
  }

  m_running = true;
  emit runningChanged();
  connectEventSocket();
  refresh();
}

void QsGoHyprlandSnapshot::stop() {
  if (!m_running)
    return;

  m_running = false;
  m_refreshPending = false;
  m_reconnectScheduled = false;
  m_eventBuffer.clear();
  if (m_eventSocket) {
    m_eventSocket->disconnect(this);
    m_eventSocket->abort();
    m_eventSocket->deleteLater();
    m_eventSocket = nullptr;
  }
  emit runningChanged();
}

bool QsGoHyprlandSnapshot::refresh() {
  if (m_refreshInFlight) {
    m_refreshPending = true;
    return true;
  }

  m_refreshInFlight = true;
  QThreadPool::globalInstance()->start([this]() {
    const SnapshotPayload payload = fetchSnapshot();
    QMetaObject::invokeMethod(
        this,
        [this, payload]() {
          m_refreshInFlight = false;
          applySnapshot(payload);

          if (m_refreshPending) {
            m_refreshPending = false;
            refresh();
          }
        },
        Qt::QueuedConnection);
  });
  return true;
}

void QsGoHyprlandSnapshot::connectEventSocket() {
  if (!m_running)
    return;

  if (m_eventSocket) {
    m_eventSocket->disconnect(this);
    m_eventSocket->abort();
    m_eventSocket->deleteLater();
  }

  m_eventSocket = new QLocalSocket(this);
  connect(m_eventSocket, &QLocalSocket::readyRead, this, [this]() {
    if (!m_eventSocket)
      return;
    m_eventBuffer += m_eventSocket->readAll();
    processEventBuffer();
  });
  connect(m_eventSocket, &QLocalSocket::disconnected, this, [this]() { scheduleReconnect(); });
  connect(m_eventSocket, &QLocalSocket::errorOccurred, this,
          [this](QLocalSocket::LocalSocketError) { scheduleReconnect(); });

  m_eventSocket->connectToServer(socketBase() + QStringLiteral("/.socket2.sock"));
  if (!m_eventSocket->waitForConnected(1000))
    scheduleReconnect();
}

void QsGoHyprlandSnapshot::scheduleReconnect() {
  if (!m_running || m_reconnectScheduled)
    return;

  m_reconnectScheduled = true;
  setError(QStringLiteral("Hyprland event socket disconnected"));
  QTimer::singleShot(300, this, [this]() {
    m_reconnectScheduled = false;
    if (!m_running)
      return;
    connectEventSocket();
    refresh();
  });
}

void QsGoHyprlandSnapshot::processEventBuffer() {
  while (true) {
    const int newline = m_eventBuffer.indexOf('\n');
    if (newline < 0)
      return;

    const QByteArray line = m_eventBuffer.left(newline).trimmed();
    m_eventBuffer.remove(0, newline + 1);
    const QByteArray eventName = line.left(line.indexOf(">>"));
    if (isRelevantEvent(QString::fromUtf8(eventName)))
      refresh();
  }
}

void QsGoHyprlandSnapshot::applySnapshot(const SnapshotPayload& payload) {
  if (!payload.valid) {
    setError(payload.error.isEmpty() ? QStringLiteral("Invalid Hyprland snapshot") : payload.error);
    return;
  }

  if (payload.activeWorkspace != m_activeWorkspace) {
    m_activeWorkspace = payload.activeWorkspace;
    emit activeWorkspaceChanged();
  }
  if (payload.clients != m_clients) {
    m_clients = payload.clients;
    emit clientsChanged();
  }

  m_revision += 1;
  emit revisionChanged();
  setError(QString());
}

void QsGoHyprlandSnapshot::setError(const QString& error) {
  if (error == m_error)
    return;
  m_error = error;
  emit errorChanged();
}
