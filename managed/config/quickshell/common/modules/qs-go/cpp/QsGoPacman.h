#pragma once
#include <QAbstractListModel>
#include <QList>
#include <QString>

class QsGoPacman : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(int updates_count READ updatesCount NOTIFY updatesCountChanged)
  Q_PROPERTY(int aur_updates_count READ aurUpdatesCount NOTIFY aurUpdatesCountChanged)
  Q_PROPERTY(int items_count READ itemsCount NOTIFY itemsCountChanged)
  Q_PROPERTY(QString updates_text READ updatesText NOTIFY updatesTextChanged)
  Q_PROPERTY(QString aur_updates_text READ aurUpdatesText NOTIFY aurUpdatesTextChanged)
  Q_PROPERTY(QString last_checked READ lastChecked NOTIFY lastCheckedChanged)
  Q_PROPERTY(bool has_updates READ hasUpdates NOTIFY hasUpdatesChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
  struct UpdateItem {
    QString name;
    QString oldVersion;
    QString newVersion;
    QString source; // "pacman" | "aur"
  };

  enum Roles { NameRole = Qt::UserRole + 1, OldVersionRole, NewVersionRole, SourceRole };

  explicit QsGoPacman(QObject* parent = nullptr);

  [[nodiscard]] auto rowCount(const QModelIndex& parent = {}) const -> int override;
  [[nodiscard]] auto data(const QModelIndex& index, int role = Qt::DisplayRole) const
      -> QVariant override;
  [[nodiscard]] auto roleNames() const -> QHash<int, QByteArray> override;

  [[nodiscard]] auto updatesCount() const -> int {
    return m_updatesCount;
  }
  [[nodiscard]] auto aurUpdatesCount() const -> int {
    return m_aurUpdatesCount;
  }
  [[nodiscard]] auto itemsCount() const -> int {
    return m_items.size();
  }
  [[nodiscard]] auto updatesText() const -> QString {
    return m_updatesText;
  }
  [[nodiscard]] auto aurUpdatesText() const -> QString {
    return m_aurUpdatesText;
  }
  [[nodiscard]] auto lastChecked() const -> QString {
    return m_lastChecked;
  }
  [[nodiscard]] auto hasUpdates() const -> bool {
    return !m_items.isEmpty();
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }

  Q_INVOKABLE auto refresh(bool noAur = false) -> bool;
  Q_INVOKABLE static auto sync() -> bool;

signals:
  void updatesCountChanged();
  void aurUpdatesCountChanged();
  void itemsCountChanged();
  void updatesTextChanged();
  void aurUpdatesTextChanged();
  void lastCheckedChanged();
  void hasUpdatesChanged();
  void errorChanged();

private:
  QList<UpdateItem> m_items;
  int m_updatesCount = 0;
  int m_aurUpdatesCount = 0;
  QString m_updatesText;
  QString m_aurUpdatesText;
  QString m_lastChecked;
  QString m_error;
};
