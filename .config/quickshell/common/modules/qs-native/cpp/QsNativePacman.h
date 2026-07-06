#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QList>
#include <QString>
#include <QVariant>

struct PacmanHandle;
struct PacmanSnapshotC;

// Pacman/AUR update provider. Rust runs `checkupdates` + `yay -Qua` on a worker
// thread and delivers a zero-copy `PacmanSnapshotC` (a #[repr(C)] struct wrapping
// a borrowed row array plus the aggregate counts/text fields); this QObject
// deep-copies it on the Qt thread and rebuilds the list model (beginResetModel +
// property setters). `sync()` fires a detached `sudo -n pacman -Sy` refresh.
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
  static void snapshotCallback(void* ctx, const PacmanSnapshotC* snap);
  void applySnapshot(const QList<UpdateItem>& items, int updatesCount, int aurUpdatesCount,
                      const QString& updatesText, const QString& aurUpdatesText,
                      const QString& lastChecked, const QString& error);

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
