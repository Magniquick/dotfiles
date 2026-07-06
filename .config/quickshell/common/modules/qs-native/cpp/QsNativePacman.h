#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QString>
#include <QVariant>

struct PacmanHandle;

// TODO(stage2): pacman/AUR update provider (STUB).
//
// Rust runs `checkupdates` + `yay -Qua` on a worker thread and delivers a JSON
// snapshot; this QObject applies it on the Qt thread (beginResetModel + property
// setters). The stub keeps the full QML-facing surface but returns empty/default
// values: rowCount() == 0 with the same role names, all counts 0, texts empty,
// has_updates false. `refresh`/`sync` return true immediately and do no real work.
class QsNativePacman : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(int updates_count READ updatesCount NOTIFY updates_countChanged)
  Q_PROPERTY(int aur_updates_count READ aurUpdatesCount NOTIFY aur_updates_countChanged)
  Q_PROPERTY(int items_count READ itemsCount NOTIFY items_countChanged)
  Q_PROPERTY(QString updates_text READ updatesText NOTIFY updates_textChanged)
  Q_PROPERTY(QString aur_updates_text READ aurUpdatesText NOTIFY aur_updates_textChanged)
  Q_PROPERTY(QString last_checked READ lastChecked NOTIFY last_checkedChanged)
  Q_PROPERTY(bool has_updates READ hasUpdates NOTIFY has_updatesChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  struct UpdateItem {
    QString name;
    QString oldVersion;
    QString newVersion;
    QString source;
  };

  enum Roles {
    NameRole = 0x0101,
    OldVersionRole = 0x0102,
    NewVersionRole = 0x0103,
    SourceRole = 0x0104,
  };

  explicit QsNativePacman(QObject* parent = nullptr);
  ~QsNativePacman() override;

  // QAbstractListModel
  [[nodiscard]] auto rowCount(const QModelIndex& parent = {}) const -> int override;
  [[nodiscard]] auto data(const QModelIndex& index, int role = Qt::DisplayRole) const
      -> QVariant override;
  [[nodiscard]] auto roleNames() const -> QHash<int, QByteArray> override;

  [[nodiscard]] auto updatesCount() const -> int { return m_updatesCount; }
  [[nodiscard]] auto aurUpdatesCount() const -> int { return m_aurUpdatesCount; }
  [[nodiscard]] auto itemsCount() const -> int { return m_itemsCount; }
  [[nodiscard]] auto updatesText() const -> QString { return m_updatesText; }
  [[nodiscard]] auto aurUpdatesText() const -> QString { return m_aurUpdatesText; }
  [[nodiscard]] auto lastChecked() const -> QString { return m_lastChecked; }
  [[nodiscard]] auto hasUpdates() const -> bool { return m_hasUpdates; }
  [[nodiscard]] auto error() const -> QString { return m_error; }

  Q_INVOKABLE auto refresh(bool no_aur) -> bool;
  Q_INVOKABLE auto sync() -> bool;

signals:
  void updates_countChanged();
  void aur_updates_countChanged();
  void items_countChanged();
  void updates_textChanged();
  void aur_updates_textChanged();
  void last_checkedChanged();
  void has_updatesChanged();
  void errorChanged();

private:
  static void snapshotCallback(void* ctx, const char* json);
  void applySnapshot(const QString& json);

  PacmanHandle* m_handle;

  QList<UpdateItem> m_items;
  int m_updatesCount = 0;
  int m_aurUpdatesCount = 0;
  int m_itemsCount = 0;
  QString m_updatesText;
  QString m_aurUpdatesText;
  QString m_lastChecked;
  bool m_hasUpdates = false;
  QString m_error;
};
