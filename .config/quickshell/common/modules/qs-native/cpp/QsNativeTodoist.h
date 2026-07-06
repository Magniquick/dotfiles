#pragma once

#include <QObject>
#include <QString>

struct TodoistHandle;

// Network-backed Todoist Sync API client. Rust performs blocking HTTPS sync on a
// worker thread and delivers a JSON snapshot ({data, error, last_updated}); this
// QObject applies it on the Qt thread. `data` is the serialized ListOutput JSON
// string, parsed in QML with JsonUtils.parseObject. `cache_path`/`prefer_cache`
// are QML-side inputs fed into each background call.
class QsNativeTodoist : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString data READ data NOTIFY dataChanged)
  Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QString last_updated READ lastUpdated NOTIFY last_updatedChanged)
  Q_PROPERTY(QString cache_path READ cachePath WRITE setCachePath NOTIFY cache_pathChanged)
  Q_PROPERTY(bool prefer_cache READ preferCache WRITE setPreferCache NOTIFY prefer_cacheChanged)

public:
  explicit QsNativeTodoist(QObject* parent = nullptr);
  ~QsNativeTodoist() override;

  [[nodiscard]] auto data() const -> QString { return m_data; }
  [[nodiscard]] auto loading() const -> bool { return m_loading; }
  [[nodiscard]] auto error() const -> QString { return m_error; }
  [[nodiscard]] auto lastUpdated() const -> QString { return m_lastUpdated; }
  [[nodiscard]] auto cachePath() const -> QString { return m_cachePath; }
  [[nodiscard]] auto preferCache() const -> bool { return m_preferCache; }

  void setCachePath(const QString& value);
  void setPreferCache(bool value);

  Q_INVOKABLE auto refresh() -> bool;
  Q_INVOKABLE auto action(const QString& verb, const QString& args_json) -> bool;

signals:
  void dataChanged();
  void loadingChanged();
  void errorChanged();
  void last_updatedChanged();
  void cache_pathChanged();
  void prefer_cacheChanged();

private:
  static void resultCallback(void* ctx, const char* json);
  void applyResult(const QString& json);

  void setLoading(bool value);
  void setError(const QString& value);
  void setLastUpdated(const QString& value);
  void setData(const QString& value);

  TodoistHandle* m_handle;

  QString m_data;
  bool m_loading = false;
  QString m_error;
  QString m_lastUpdated;
  QString m_cachePath;
  bool m_preferCache = true;
};
