#include "QsNativeUnifiedLyrics.h"
#include "unifiedlyrics_api.h"

#include <QByteArray>
#include <QJsonArray>
#include <QJsonDocument>
#include <QMetaObject>
#include <QString>

namespace {

// `json` is borrowed (only valid for the duration of the callback that handed
// it to us), so this must not retain the pointer or free it -- only parse.
[[nodiscard]] auto parseLinesJson(const char* json) -> QVariantList {
  if (json == nullptr) {
    return {};
  }
  const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(json));
  return doc.isArray() ? doc.array().toVariantList() : QVariantList{};
}

} // namespace

QsNativeUnifiedLyrics::QsNativeUnifiedLyrics(QObject* parent)
    : QObject(parent), m_handle(QsNative_UnifiedLyrics_New()) {}

QsNativeUnifiedLyrics::~QsNativeUnifiedLyrics() {
  QsNative_UnifiedLyrics_Delete(m_handle);
}

auto QsNativeUnifiedLyrics::refresh(const QString& spotifyTrackRef, const QString& trackName,
                                    const QString& artistName, const QString& albumName,
                                    const QString& lengthMicros) -> bool {
  const QByteArray ref = spotifyTrackRef.toUtf8();
  const QByteArray track = trackName.toUtf8();
  const QByteArray artist = artistName.toUtf8();
  const QByteArray album = albumName.toUtf8();
  const QByteArray length = lengthMicros.toUtf8();

  const bool accepted = QsNative_UnifiedLyrics_Refresh(
      m_handle, this, &QsNativeUnifiedLyrics::resultCallback, ref.constData(), track.constData(),
      artist.constData(), album.constData(), length.constData());

  if (!accepted) {
    setError(QStringLiteral("trackName and artistName required"));
    setStatus(QStringLiteral("Error"));
    setLoaded(false);
    return false;
  }

  // Enter the "fetching" state synchronously; the eventual outcome arrives
  // later (queued) via resultCallback -> applyResult.
  setBusy(true);
  setLoaded(false);
  setError(QString());
  setStatus(QStringLiteral("Fetching lyrics..."));
  setSource(QString());
  setSyncType(QString());
  setMetadata(QVariantMap());
  setLines(QVariantList());
  return true;
}

void QsNativeUnifiedLyrics::resultCallback(void* ctx, const UnifiedLyricsResultC* result) {
  auto* self = static_cast<QsNativeUnifiedLyrics*>(ctx);
  if (result == nullptr) {
    return;
  }

  // Deep-copy synchronously: the char* fields are only valid for this call.
  Result r;
  r.loaded = result->loaded;
  r.status = QString::fromUtf8(result->status);
  r.error = QString::fromUtf8(result->error);
  r.source = QString::fromUtf8(result->source);
  r.syncType = QString::fromUtf8(result->sync_type);
  if (r.loaded) {
    // Matches the original: "provider" is always inserted, even if empty
    // (it never is in practice -- every provider path sets a non-empty
    // static name before a result is delivered here).
    r.metadata.insert(QStringLiteral("provider"), QString::fromUtf8(result->provider));
    r.lines = parseLinesJson(result->lines_json);
  }

  QMetaObject::invokeMethod(
      self, [self, r]() { self->applyResult(r); }, Qt::QueuedConnection);
}

void QsNativeUnifiedLyrics::applyResult(const Result& result) {
  if (result.loaded) {
    setSource(result.source);
    setSyncType(result.syncType);
    setMetadata(result.metadata);
    setLines(result.lines);
  }
  setStatus(result.status);
  setError(result.error);
  setBusy(false);
  setLoaded(result.loaded);
}

void QsNativeUnifiedLyrics::setBusy(bool value) {
  if (m_busy == value) {
    return;
  }
  m_busy = value;
  emit busyChanged();
}

void QsNativeUnifiedLyrics::setLoaded(bool value) {
  if (m_loaded == value) {
    return;
  }
  m_loaded = value;
  emit loadedChanged();
}

void QsNativeUnifiedLyrics::setStatus(const QString& value) {
  if (m_status == value) {
    return;
  }
  m_status = value;
  emit statusChanged();
}

void QsNativeUnifiedLyrics::setError(const QString& value) {
  if (m_error == value) {
    return;
  }
  m_error = value;
  emit errorChanged();
}

void QsNativeUnifiedLyrics::setSource(const QString& value) {
  if (m_source == value) {
    return;
  }
  m_source = value;
  emit sourceChanged();
}

void QsNativeUnifiedLyrics::setSyncType(const QString& value) {
  if (m_syncType == value) {
    return;
  }
  m_syncType = value;
  emit syncTypeChanged();
}

void QsNativeUnifiedLyrics::setMetadata(const QVariantMap& value) {
  if (m_metadata == value) {
    return;
  }
  m_metadata = value;
  emit metadataChanged();
}

void QsNativeUnifiedLyrics::setLines(const QVariantList& value) {
  // Mirrors the original: lines is always assigned + notified, unguarded.
  m_lines = value;
  emit linesChanged();
}
