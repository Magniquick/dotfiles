#include "UnifiedLyricsClient.h"

#include <QtConcurrent/QtConcurrent>
#include <QtGlobal>

#include "libunifiedlyrics_go.h"

UnifiedLyricsClient::UnifiedLyricsClient(QObject* parent) : QObject(parent) {
  m_timeout.setSingleShot(true);
  connect(&m_timeout, &QTimer::timeout, this, [this]() -> void {
    setError(QStringLiteral("Timeout while fetching lyrics"));
    setStatus(QStringLiteral("Timed out"));
    ++m_requestId;
    setBusy(false);
    setLoaded(false);
  });

  connect(&m_watcher, &QFutureWatcher<UnifiedLyricsBackendResult>::finished, this,
          [this]() -> void {
            stopTimeout();

            const UnifiedLyricsBackendResult out = m_watcher.result();
            const quint64 finishedId = m_watcher.property("requestId").toULongLong();
            if (finishedId != m_requestId) {
              return;
            }

            if (!out.valid) {
              setError(QStringLiteral("Empty response from lyrics backend"));
              setStatus(QStringLiteral("Error"));
              setBusy(false);
              setLoaded(false);
              return;
            }

            if (out.error) {
              qWarning().noquote()
                  << "UnifiedLyricsClient backend error"
                  << "message="
                  << (out.message.isEmpty() ? QStringLiteral("Unknown error") : out.message);
              setError(out.message.isEmpty() ? QStringLiteral("Unknown error") : out.message);
              setStatus(QStringLiteral("Error"));
              setBusy(false);
              setLoaded(false);
              return;
            }

            setSource(out.source);
            setSyncType(out.syncType);
            setMetadata(QVariantMap{{QStringLiteral("provider"), out.provider}});
            setLines(out.lines);
            qInfo().noquote() << "UnifiedLyricsClient loaded"
                              << "source=" << out.source << "provider=" << out.provider
                              << "syncType=" << out.syncType << "lines=" << out.lines.size();

            setStatus(QStringLiteral("OK"));
            setBusy(false);
            setLoaded(true);
          });
}

void UnifiedLyricsClient::setBusy(bool busy) {
  if (m_busy == busy) {
    return;
  }
  m_busy = busy;
  emit busyChanged();
}

void UnifiedLyricsClient::setLoaded(bool loaded) {
  if (m_loaded == loaded) {
    return;
  }
  m_loaded = loaded;
  emit loadedChanged();
}

void UnifiedLyricsClient::setStatus(const QString& status) {
  if (m_status == status) {
    return;
  }
  m_status = status;
  emit statusChanged();
}

void UnifiedLyricsClient::setError(const QString& error) {
  if (m_error == error) {
    return;
  }
  m_error = error;
  emit errorChanged();
}

void UnifiedLyricsClient::setSource(const QString& source) {
  if (m_source == source) {
    return;
  }
  m_source = source;
  emit sourceChanged();
}

void UnifiedLyricsClient::setSyncType(const QString& syncType) {
  if (m_syncType == syncType) {
    return;
  }
  m_syncType = syncType;
  emit syncTypeChanged();
}

void UnifiedLyricsClient::setLines(const QVariantList& lines) {
  m_lines = lines;
  emit linesChanged();
}

void UnifiedLyricsClient::setMetadata(const QVariantMap& metadata) {
  if (m_metadata == metadata) {
    return;
  }
  m_metadata = metadata;
  emit metadataChanged();
}

void UnifiedLyricsClient::startTimeout(int ms) {
  if (ms > 0) {
    m_timeout.start(ms);
  }
}

void UnifiedLyricsClient::stopTimeout() {
  if (m_timeout.isActive()) {
    m_timeout.stop();
  }
}

auto UnifiedLyricsClient::refresh(const QString& spotifyTrackRef, const QString& trackName,
                                  const QString& artistName, const QString& albumName,
                                  const QString& lengthMicros) -> bool {
  if (spotifyTrackRef.trimmed().isEmpty() &&
      (trackName.trimmed().isEmpty() || artistName.trimmed().isEmpty())) {
    setError(QStringLiteral("spotifyTrackRef or (trackName+artistName) required"));
    setStatus(QStringLiteral("Error"));
    setLoaded(false);
    return false;
  }

  qInfo().noquote() << "UnifiedLyricsClient refresh"
                    << "track=" << trackName.trimmed() << "artist=" << artistName.trimmed()
                    << "album=" << albumName.trimmed() << "spotifyRef=" << spotifyTrackRef.trimmed()
                    << "lengthMicros=" << lengthMicros.trimmed();

  setBusy(true);
  setLoaded(false);
  setError(QString());
  setStatus(QStringLiteral("Fetching lyrics..."));
  setSource(QString());
  setSyncType(QString());
  setMetadata(QVariantMap{});
  setLines(QVariantList{});

  const QByteArray spdcUtf8;
  const QByteArray spotifyRefUtf8 = spotifyTrackRef.trimmed().toUtf8();
  const QByteArray trackUtf8 = trackName.trimmed().toUtf8();
  const QByteArray artistUtf8 = artistName.trimmed().toUtf8();
  const QByteArray albumUtf8 = albumName.trimmed().toUtf8();
  const QByteArray lengthMicrosUtf8 = lengthMicros.trimmed().toUtf8();

  const quint64 requestId = ++m_requestId;
  m_watcher.setProperty("requestId", QVariant::fromValue<qulonglong>(requestId));
  startTimeout(30000);

  m_watcher.setFuture(QtConcurrent::run([spdcUtf8, spotifyRefUtf8, trackUtf8, artistUtf8, albumUtf8,
                                         lengthMicrosUtf8]() -> UnifiedLyricsBackendResult {
    UnifiedLyricsBackendResult result;
    UnifiedLyricsResult* out = UnifiedLyrics_GetLyrics(
        const_cast<char*>(spdcUtf8.constData()), const_cast<char*>(spotifyRefUtf8.constData()),
        const_cast<char*>(trackUtf8.constData()), const_cast<char*>(artistUtf8.constData()),
        const_cast<char*>(albumUtf8.constData()), const_cast<char*>(lengthMicrosUtf8.constData()));
    if (!out) {
      return result;
    }

    result.valid = true;
    result.error = out->error;
    if (out->message) {
      result.message = QString::fromUtf8(out->message);
    }
    if (out->source) {
      result.source = QString::fromUtf8(out->source);
    }
    if (out->syncType) {
      result.syncType = QString::fromUtf8(out->syncType);
    }
    if (out->provider) {
      result.provider = QString::fromUtf8(out->provider);
    }

    result.lines.reserve(static_cast<int>(out->lineCount));
    for (size_t i = 0; i < out->lineCount; ++i) {
      const UnifiedLyricsLine& ln = out->lines[i];
      QVariantMap row;
      row.insert(QStringLiteral("startTimeMs"),
                 ln.startTimeMs ? QString::fromUtf8(ln.startTimeMs) : QString());
      row.insert(QStringLiteral("endTimeMs"),
                 ln.endTimeMs ? QString::fromUtf8(ln.endTimeMs) : QString());
      row.insert(QStringLiteral("words"), ln.words ? QString::fromUtf8(ln.words) : QString());
      QVariantList segments;
      segments.reserve(static_cast<int>(ln.segmentCount));
      for (size_t j = 0; j < ln.segmentCount; ++j) {
        const UnifiedLyricsSegment& segment = ln.segments[j];
        QVariantMap segmentMap;
        segmentMap.insert(QStringLiteral("startTimeMs"),
                          segment.startTimeMs ? QString::fromUtf8(segment.startTimeMs) : QString());
        segmentMap.insert(QStringLiteral("endTimeMs"),
                          segment.endTimeMs ? QString::fromUtf8(segment.endTimeMs) : QString());
        segmentMap.insert(QStringLiteral("text"),
                          segment.text ? QString::fromUtf8(segment.text) : QString());
        segments.push_back(segmentMap);
      }
      row.insert(QStringLiteral("segments"), segments);
      result.lines.push_back(row);
    }

    UnifiedLyrics_FreeResult(out);
    return result;
  }));

  return true;
}
