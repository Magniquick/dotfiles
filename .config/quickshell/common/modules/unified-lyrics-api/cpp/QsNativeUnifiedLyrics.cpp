#include "QsNativeUnifiedLyrics.h"
#include "unifiedlyrics_api.h"

QsNativeUnifiedLyrics::QsNativeUnifiedLyrics(QObject* parent)
    : QObject(parent), m_handle(QsNative_UnifiedLyrics_New()) {}

QsNativeUnifiedLyrics::~QsNativeUnifiedLyrics() {
  QsNative_UnifiedLyrics_Delete(m_handle);
}

// TODO(stage2): dispatch to the threaded fetch pipeline and publish results via
// a queued callback. For now this only validates inputs and never mutates state,
// mirroring the Rust stub's return contract (false when track/artist is empty).
auto QsNativeUnifiedLyrics::refresh(const QString& spotifyTrackRef, const QString& trackName,
                                    const QString& artistName, const QString& albumName,
                                    const QString& lengthMicros) -> bool {
  const QByteArray ref = spotifyTrackRef.toUtf8();
  const QByteArray track = trackName.toUtf8();
  const QByteArray artist = artistName.toUtf8();
  const QByteArray album = albumName.toUtf8();
  const QByteArray length = lengthMicros.toUtf8();
  return QsNative_UnifiedLyrics_Refresh(m_handle, ref.constData(), track.constData(),
                                        artist.constData(), album.constData(),
                                        length.constData());
}
