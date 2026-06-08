#pragma once

#include <QFutureWatcher>
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

struct UnifiedLyricsBackendResult {
  bool valid = false;
  bool error = false;
  QString message;
  QString source;
  QString syncType;
  QString provider;
  QVariantList lines;
};

class UnifiedLyricsClient : public QObject {
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
  explicit UnifiedLyricsClient(QObject* parent = nullptr);

  auto busy() const -> bool {
    return m_busy;
  }
  auto loaded() const -> bool {
    return m_loaded;
  }
  auto status() const -> QString {
    return m_status;
  }
  auto error() const -> QString {
    return m_error;
  }
  auto source() const -> QString {
    return m_source;
  }
  auto syncType() const -> QString {
    return m_syncType;
  }
  auto metadata() const -> QVariantMap {
    return m_metadata;
  }
  auto lines() const -> QVariantList {
    return m_lines;
  }

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
  void setBusy(bool busy);
  void setLoaded(bool loaded);
  void setStatus(const QString& status);
  void setError(const QString& error);
  void setSource(const QString& source);
  void setSyncType(const QString& syncType);
  void setMetadata(const QVariantMap& metadata);
  void setLines(const QVariantList& lines);

  void startTimeout(int ms);
  void stopTimeout();

  QTimer m_timeout;
  QFutureWatcher<UnifiedLyricsBackendResult> m_watcher;
  quint64 m_requestId = 0;

  bool m_busy = false;
  bool m_loaded = false;
  QString m_status;
  QString m_error;
  QString m_source;
  QString m_syncType;
  QVariantMap m_metadata;
  QVariantList m_lines;
};
