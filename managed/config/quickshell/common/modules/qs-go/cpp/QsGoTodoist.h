#pragma once
#include <QObject>

class QsGoTodoist : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString data READ data NOTIFY dataChanged)
  Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString last_updated READ lastUpdated NOTIFY lastUpdatedChanged)
  Q_PROPERTY(QString cache_path READ cachePath WRITE setCachePath NOTIFY cachePathChanged)
  Q_PROPERTY(bool prefer_cache READ preferCache WRITE setPreferCache NOTIFY preferCacheChanged)

public:
  explicit QsGoTodoist(QObject* parent = nullptr);

  [[nodiscard]] auto data() const -> QString {
    return m_data;
  }
  [[nodiscard]] auto loading() const -> bool {
    return m_loading;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }
  [[nodiscard]] auto lastUpdated() const -> QString {
    return m_lastUpdated;
  }
  [[nodiscard]] auto cachePath() const -> QString {
    return m_cachePath;
  }
  [[nodiscard]] auto preferCache() const -> bool {
    return m_preferCache;
  }

  void setCachePath(const QString& v);
  void setPreferCache(bool v);

  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE auto action(const QString& verb, const QString& argsJson) -> bool;

signals:
  void dataChanged();
  void loadingChanged();
  void errorChanged();
  void lastUpdatedChanged();
  void cachePathChanged();
  void preferCacheChanged();

private:
  QString m_data;
  bool m_loading = false;
  QString m_error;
  QString m_lastUpdated;
  QString m_cachePath;
  bool m_preferCache = true;
};
