#include "SpotifyLyricsClient.h"

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QtConcurrent/QtConcurrent>

#include "spotifylyrics_go_api.h"

namespace {

static QString trimQuotes(QString v)
{
  v = v.trimmed();
  if (v.size() >= 2) {
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\'')))
      return v.mid(1, v.size() - 2);
  }
  return v;
}

} // namespace

SpotifyLyricsClient::SpotifyLyricsClient(QObject *parent)
    : QObject(parent)
{
  m_timeout.setSingleShot(true);
  connect(&m_timeout, &QTimer::timeout, this, [this]() {
    setError(QStringLiteral("Timeout while fetching lyrics"));
    setStatus(QStringLiteral("Timed out"));
    // We can't reliably cancel the in-flight Go call, so ignore its result.
    ++m_requestId;
    setBusy(false);
    setLoaded(false);
  });

  connect(&m_watcher, &QFutureWatcher<QByteArray>::finished, this, [this]() {
    stopTimeout();

    const QByteArray out = m_watcher.result();
    const quint64 finishedId = m_watcher.property("requestId").toULongLong();

    if (finishedId != m_requestId) {
      // Stale result (timed out or superseded).
      return;
    }

    if (out.isEmpty()) {
      setError(QStringLiteral("Empty response from lyrics backend"));
      setStatus(QStringLiteral("Error"));
      setBusy(false);
      setLoaded(false);
      return;
    }

    QJsonParseError pe;
    const QJsonDocument doc = QJsonDocument::fromJson(out, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
      setError(QStringLiteral("Invalid JSON from lyrics backend"));
      setStatus(QStringLiteral("Error"));
      setBusy(false);
      setLoaded(false);
      return;
    }

    const QJsonObject obj = doc.object();
    if (obj.value(QStringLiteral("error")).toBool(false)) {
      setError(obj.value(QStringLiteral("message")).toString(QStringLiteral("Unknown error")));
      setStatus(QStringLiteral("Error"));
      setBusy(false);
      setLoaded(false);
      return;
    }

    setSyncType(obj.value(QStringLiteral("syncType")).toString());

    QVariantList lines;
    const QJsonValue linesVal = obj.value(QStringLiteral("lines"));
    if (linesVal.isArray()) {
      const QJsonArray arr = linesVal.toArray();
      lines.reserve(arr.size());
      for (const auto &v : arr) {
        if (!v.isObject())
          continue;
        const QJsonObject ln = v.toObject();
        QVariantMap m;
        m.insert(QStringLiteral("startTimeMs"), ln.value(QStringLiteral("startTimeMs")).toString());
        m.insert(QStringLiteral("words"), ln.value(QStringLiteral("words")).toString());
        lines.push_back(m);
      }
    }
    setLines(lines);

    setStatus(QStringLiteral("OK"));
    setBusy(false);
    setLoaded(true);
  });
}

void SpotifyLyricsClient::setBusy(bool busy)
{
  if (m_busy == busy)
    return;
  m_busy = busy;
  emit busyChanged();
}

void SpotifyLyricsClient::setLoaded(bool loaded)
{
  if (m_loaded == loaded)
    return;
  m_loaded = loaded;
  emit loadedChanged();
}

void SpotifyLyricsClient::setStatus(const QString &status)
{
  if (m_status == status)
    return;
  m_status = status;
  emit statusChanged();
}

void SpotifyLyricsClient::setError(const QString &error)
{
  if (m_error == error)
    return;
  m_error = error;
  emit errorChanged();
}

void SpotifyLyricsClient::setSyncType(const QString &syncType)
{
  if (m_syncType == syncType)
    return;
  m_syncType = syncType;
  emit syncTypeChanged();
}

void SpotifyLyricsClient::setTrackId(const QString &trackId)
{
  if (m_trackId == trackId)
    return;
  m_trackId = trackId;
  emit trackIdChanged();
}

void SpotifyLyricsClient::setLines(const QVariantList &lines)
{
  m_lines = lines;
  emit linesChanged();
}

void SpotifyLyricsClient::startTimeout(int ms)
{
  if (ms > 0)
    m_timeout.start(ms);
}

void SpotifyLyricsClient::stopTimeout()
{
  if (m_timeout.isActive())
    m_timeout.stop();
}

QString SpotifyLyricsClient::extractSpDcFromEnvFile(const QString &envFile, QString *errOut)
{
  if (errOut)
    *errOut = QString();

  if (envFile.trimmed().isEmpty()) {
    if (errOut)
      *errOut = QStringLiteral("envFile is empty");
    return QString();
  }

  QFile f(envFile);
  if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    if (errOut)
      *errOut = QStringLiteral("Failed to open env file: %1").arg(envFile);
    return QString();
  }

  const auto bytes = f.readAll();
  const auto text = QString::fromUtf8(bytes);

  // Accept lines like:
  // SP_DC=...
  // export SP_DC=...
  // SP_DC="..."
  const QRegularExpression re(QStringLiteral(R"((?:^|\n)\s*(?:export\s+)?SP_DC\s*=\s*([^\n#]+))"));
  const auto m = re.match(text);
  if (!m.hasMatch()) {
    if (errOut)
      *errOut = QStringLiteral("SP_DC not found in env file");
    return QString();
  }

  return trimQuotes(m.captured(1));
}

bool SpotifyLyricsClient::refreshFromEnv(const QString &envFile, const QString &trackIdOrUrl)
{
  if (trackIdOrUrl.trimmed().isEmpty()) {
    setError(QStringLiteral("trackIdOrUrl is empty"));
    setStatus(QStringLiteral("Error"));
    setLoaded(false);
    return false;
  }

  QString err;
  const QString spdc = extractSpDcFromEnvFile(envFile, &err);
  if (spdc.isEmpty()) {
    setError(err.isEmpty() ? QStringLiteral("Missing SP_DC") : err);
    setStatus(QStringLiteral("Error"));
    setLoaded(false);
    return false;
  }

  setBusy(true);
  setLoaded(false);
  setError(QString());
  setStatus(QStringLiteral("Fetching lyrics..."));
  setSyncType(QString());
  setLines(QVariantList{});

  // Try to set trackId if it looks like a plain ID; otherwise keep the raw input.
  if (trackIdOrUrl.startsWith(QStringLiteral("http")) || trackIdOrUrl.contains(QStringLiteral("spotify:"))) {
    setTrackId(QString());
  } else {
    setTrackId(trackIdOrUrl.trimmed());
  }

  const QByteArray spdcUtf8 = spdc.toUtf8();
  const QByteArray trackUtf8 = trackIdOrUrl.trimmed().toUtf8();
  const quint64 requestId = ++m_requestId;

  m_watcher.setProperty("requestId", QVariant::fromValue<qulonglong>(requestId));
  startTimeout(30000);

  m_watcher.setFuture(QtConcurrent::run([spdcUtf8, trackUtf8]() -> QByteArray {
    char *out = SpotifyLyrics_GetLyricsJson(spdcUtf8.constData(), trackUtf8.constData());
    if (!out)
      return QByteArray();
    QByteArray bytes(out);
    SpotifyLyrics_FreeString(out);
    return bytes;
  }));
  return true;
}
