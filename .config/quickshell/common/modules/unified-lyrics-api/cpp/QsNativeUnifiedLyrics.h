#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

struct UnifiedLyricsHandle;

// STUB lyrics client. Preserves the UnifiedLyricsClient QML surface (8 read-only
// NOTIFY properties + refresh()) but performs no network fetch: every property
// stays at its default and refresh() only validates its inputs.
// TODO(stage2): restore threaded fetch + queued result delivery.
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
