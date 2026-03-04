#include "UnifiedLyricsClient.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QtGlobal>
#include <QtConcurrent/QtConcurrent>

#include "unifiedlyrics_go_api.h"

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

UnifiedLyricsClient::UnifiedLyricsClient(QObject *parent)
    : QObject(parent)
{
  m_timeout.setSingleShot(true);
  connect(&m_timeout, &QTimer::timeout, this, [this]() {
    setError(QStringLiteral("Timeout while fetching lyrics"));
    setStatus(QStringLiteral("Timed out"));
    ++m_requestId;
    setBusy(false);
    setLoaded(false);
  });

  connect(&m_watcher, &QFutureWatcher<QByteArray>::finished, this, [this]() {
    stopTimeout();

    const QByteArray out = m_watcher.result();
    const quint64 finishedId = m_watcher.property("requestId").toULongLong();
    if (finishedId != m_requestId)
      return;

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

    setSource(obj.value(QStringLiteral("source")).toString());
    setSyncType(obj.value(QStringLiteral("syncType")).toString());
    setMetadata(obj.value(QStringLiteral("metadata")).toObject().toVariantMap());

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

void UnifiedLyricsClient::setBusy(bool busy)
{
  if (m_busy == busy)
    return;
  m_busy = busy;
  emit busyChanged();
}

void UnifiedLyricsClient::setLoaded(bool loaded)
{
  if (m_loaded == loaded)
    return;
  m_loaded = loaded;
  emit loadedChanged();
}

void UnifiedLyricsClient::setStatus(const QString &status)
{
  if (m_status == status)
    return;
  m_status = status;
  emit statusChanged();
}

void UnifiedLyricsClient::setError(const QString &error)
{
  if (m_error == error)
    return;
  m_error = error;
  emit errorChanged();
}

void UnifiedLyricsClient::setSource(const QString &source)
{
  if (m_source == source)
    return;
  m_source = source;
  emit sourceChanged();
}

void UnifiedLyricsClient::setSyncType(const QString &syncType)
{
  if (m_syncType == syncType)
    return;
  m_syncType = syncType;
  emit syncTypeChanged();
}

void UnifiedLyricsClient::setLines(const QVariantList &lines)
{
  m_lines = lines;
  emit linesChanged();
}

void UnifiedLyricsClient::setMetadata(const QVariantMap &metadata)
{
  if (m_metadata == metadata)
    return;
  m_metadata = metadata;
  emit metadataChanged();
}

void UnifiedLyricsClient::startTimeout(int ms)
{
  if (ms > 0)
    m_timeout.start(ms);
}

void UnifiedLyricsClient::stopTimeout()
{
  if (m_timeout.isActive())
    m_timeout.stop();
}

QString UnifiedLyricsClient::extractSpDcFromEnvFile(const QString &envFile, QString *errOut)
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

  const auto text = QString::fromUtf8(f.readAll());
  const QRegularExpression re(QStringLiteral(R"((?:^|\n)\s*(?:export\s+)?SP_DC\s*=\s*([^\n#]+))"));
  const auto m = re.match(text);
  if (!m.hasMatch()) {
    if (errOut)
      *errOut = QStringLiteral("SP_DC not found in env file");
    return QString();
  }

  return trimQuotes(m.captured(1));
}

bool UnifiedLyricsClient::refreshFromEnv(const QString &envFile,
                                         const QString &spotifyTrackRef,
                                         const QString &trackName,
                                         const QString &artistName,
                                         const QString &albumName,
                                         int durationSeconds)
{
  if (spotifyTrackRef.trimmed().isEmpty() && (trackName.trimmed().isEmpty() || artistName.trimmed().isEmpty())) {
    setError(QStringLiteral("spotifyTrackRef or (trackName+artistName) required"));
    setStatus(QStringLiteral("Error"));
    setLoaded(false);
    return false;
  }

  const QString spdc = extractSpDcFromEnvFile(envFile, nullptr);

  setBusy(true);
  setLoaded(false);
  setError(QString());
  setStatus(QStringLiteral("Fetching lyrics..."));
  setSource(QString());
  setSyncType(QString());
  setMetadata(QVariantMap{});
  setLines(QVariantList{});

  const QByteArray spdcUtf8 = spdc.toUtf8();
  const QByteArray spotifyRefUtf8 = spotifyTrackRef.trimmed().toUtf8();
  const QByteArray trackUtf8 = trackName.trimmed().toUtf8();
  const QByteArray artistUtf8 = artistName.trimmed().toUtf8();
  const QByteArray albumUtf8 = albumName.trimmed().toUtf8();
  const QByteArray durationUtf8 = QByteArray::number(qMax(0, durationSeconds));

  const quint64 requestId = ++m_requestId;
  m_watcher.setProperty("requestId", QVariant::fromValue<qulonglong>(requestId));
  startTimeout(30000);

  m_watcher.setFuture(QtConcurrent::run([spdcUtf8,
                                         spotifyRefUtf8,
                                         trackUtf8,
                                         artistUtf8,
                                         albumUtf8,
                                         durationUtf8]() -> QByteArray {
    char *out = UnifiedLyrics_GetLyricsJson(spdcUtf8.constData(),
                                            spotifyRefUtf8.constData(),
                                            trackUtf8.constData(),
                                            artistUtf8.constData(),
                                            albumUtf8.constData(),
                                            durationUtf8.constData());
    if (!out)
      return QByteArray();
    QByteArray bytes(out);
    UnifiedLyrics_FreeString(out);
    return bytes;
  }));

  return true;
}
