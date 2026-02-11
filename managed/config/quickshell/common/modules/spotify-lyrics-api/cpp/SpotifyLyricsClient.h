#pragma once

#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QFutureWatcher>

class SpotifyLyricsClient : public QObject
{
  Q_OBJECT

  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(bool loaded READ loaded NOTIFY loadedChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString syncType READ syncType NOTIFY syncTypeChanged)
  Q_PROPERTY(QString trackId READ trackId NOTIFY trackIdChanged)
  Q_PROPERTY(QVariantList lines READ lines NOTIFY linesChanged)

public:
  explicit SpotifyLyricsClient(QObject *parent = nullptr);

  bool busy() const { return m_busy; }
  bool loaded() const { return m_loaded; }
  QString status() const { return m_status; }
  QString error() const { return m_error; }
  QString syncType() const { return m_syncType; }
  QString trackId() const { return m_trackId; }
  QVariantList lines() const { return m_lines; }

  Q_INVOKABLE bool refreshFromEnv(const QString &envFile, const QString &trackIdOrUrl);

signals:
  void busyChanged();
  void loadedChanged();
  void statusChanged();
  void errorChanged();
  void syncTypeChanged();
  void trackIdChanged();
  void linesChanged();

private:
  void setBusy(bool busy);
  void setLoaded(bool loaded);
  void setStatus(const QString &status);
  void setError(const QString &error);
  void setSyncType(const QString &syncType);
  void setTrackId(const QString &trackId);
  void setLines(const QVariantList &lines);

  static QString extractSpDcFromEnvFile(const QString &envFile, QString *errOut);
  void startTimeout(int ms);
  void stopTimeout();

  QTimer m_timeout;
  QFutureWatcher<QByteArray> m_watcher;
  quint64 m_requestId = 0;

  bool m_busy = false;
  bool m_loaded = false;
  QString m_status;
  QString m_error;
  QString m_syncType;
  QString m_trackId;
  QVariantList m_lines;
};
