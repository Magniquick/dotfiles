#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

struct UnifiedLyricsHandle;
struct UnifiedLyricsResultC;

// Unified lyrics client (Spotify/NetEase/LRCLIB). `refresh()` validates its
// inputs synchronously (setting `error`/`status` and returning false if
// track/artist is missing, mirroring the Rust-side early return) and otherwise
// puts the object into the "fetching" state immediately, then lets Rust run the
// provider pipeline (+ 30s watchdog) on background threads. Exactly one
// `resultCallback` fires per accepted refresh, carrying the terminal outcome
// (success/error/timeout) as a borrowed `UnifiedLyricsResultC`; this QObject
// deep-copies it and applies it on the Qt thread.
class QsNativeUnifiedLyrics : public QObject {
  Q_OBJECT

  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
  Q_PROPERTY(QString syncType READ syncType NOTIFY syncTypeChanged)
  Q_PROPERTY(QVariantMap metadata READ metadata NOTIFY metadataChanged)
  Q_PROPERTY(QVariantList lines READ lines NOTIFY linesChanged)

public:
  explicit QsNativeUnifiedLyrics(QObject* parent = nullptr);
  ~QsNativeUnifiedLyrics() override;

  [[nodiscard]] auto busy() const -> bool { return m_busy; }
  [[nodiscard]] auto loaded() const -> bool { return m_loaded; }
  [[nodiscard]] auto status() const -> QString { return m_status; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto source() const -> QString { return m_source; }
  [[nodiscard]] auto syncType() const -> QString { return m_syncType; }
  [[nodiscard]] auto metadata() const -> QVariantMap { return m_metadata; }
  [[nodiscard]] auto lines() const -> QVariantList { return m_lines; }

  Q_INVOKABLE auto refresh(const QString& spotifyTrackRef, const QString& trackName,
                           const QString& artistName, const QString& albumName,
                           const QString& lengthMicros) -> bool;

signals:
  void busyChanged();
  void loadedChanged();
  void statusChanged();
  void errorChanged();
  void sourceChanged();
  void syncTypeChanged();
  void metadataChanged();
  void linesChanged();

private:
  // Qt-owned copy of a terminal refresh outcome (deep-copied off the borrowed
  // UnifiedLyricsResultC during the callback).
  struct Result {
    bool loaded = false;
    QString status;
    QString error;
    QString source;
    QString syncType;
    QVariantMap metadata;
    QVariantList lines;
  };

  static void resultCallback(void* ctx, const UnifiedLyricsResultC* result);
  void applyResult(const Result& result);

  void setBusy(bool value);
  void setLoaded(bool value);
  void setStatus(const QString& value);
  void setError(const QString& value);
  void setSource(const QString& value);
  void setSyncType(const QString& value);
  void setMetadata(const QVariantMap& value);
  void setLines(const QVariantList& value);

  UnifiedLyricsHandle* m_handle;

  bool m_busy = false;
  bool m_loaded = false;
  QString m_status;
  QString m_error;
  QString m_source;
  QString m_syncType;
  QVariantMap m_metadata;
  QVariantList m_lines;
};
