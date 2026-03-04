#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QFutureWatcher>

struct UnifiedLyricsBackendResult {
  bool valid = false;
  bool error = false;
  QString message;
  QString source;
  QString syncType;
  QString provider;
  QVariantList lines;
};

class UnifiedLyricsClient : public QObject
{
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
  explicit UnifiedLyricsClient(QObject *parent = nullptr);

  bool busy() const { return m_busy; }
  bool loaded() const { return m_loaded; }
  QString status() const { return m_status; }
  QString error() const { return m_error; }
  QString source() const { return m_source; }
  QString syncType() const { return m_syncType; }
  QVariantMap metadata() const { return m_metadata; }
  QVariantList lines() const { return m_lines; }

  Q_INVOKABLE bool refreshFromEnv(const QString &envFile,
                                  const QString &spotifyTrackRef,
                                  const QString &trackName,
                                  const QString &artistName,
                                  const QString &albumName,
                                  const QString &lengthMicros);

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
  void setStatus(const QString &status);
  void setError(const QString &error);
  void setSource(const QString &source);
  void setSyncType(const QString &syncType);
  void setMetadata(const QVariantMap &metadata);
  void setLines(const QVariantList &lines);

  static QString extractSpDcFromEnvFile(const QString &envFile, QString *errOut);
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
