#pragma once
#include <QAbstractListModel>
#include <QList>
#include <QString>

class QsGoPacman : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(int    updates_count     READ updatesCount     NOTIFY updatesCountChanged)
  Q_PROPERTY(int    aur_updates_count READ aurUpdatesCount  NOTIFY aurUpdatesCountChanged)
  Q_PROPERTY(int    items_count       READ itemsCount       NOTIFY itemsCountChanged)
  Q_PROPERTY(QString updates_text     READ updatesText      NOTIFY updatesTextChanged)
  Q_PROPERTY(QString aur_updates_text READ aurUpdatesText   NOTIFY aurUpdatesTextChanged)
  Q_PROPERTY(QString last_checked     READ lastChecked      NOTIFY lastCheckedChanged)
  Q_PROPERTY(bool    has_updates      READ hasUpdates       NOTIFY hasUpdatesChanged)
  Q_PROPERTY(QString error            READ error            NOTIFY errorChanged)

public:
  struct UpdateItem {
    QString name;
    QString oldVersion;
    QString newVersion;
    QString source; // "pacman" | "aur"
  };

  enum Roles {
    NameRole       = Qt::UserRole + 1,
    OldVersionRole,
    NewVersionRole,
    SourceRole
  };

  explicit QsGoPacman(QObject* parent = nullptr);

  int     rowCount(const QModelIndex& parent = {}) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  int     updatesCount()    const { return m_updatesCount; }
  int     aurUpdatesCount() const { return m_aurUpdatesCount; }
  int     itemsCount()      const { return m_items.size(); }
  QString updatesText()     const { return m_updatesText; }
  QString aurUpdatesText()  const { return m_aurUpdatesText; }
  QString lastChecked()     const { return m_lastChecked; }
  bool    hasUpdates()      const { return !m_items.isEmpty(); }
  QString error()           const { return m_error; }

  Q_INVOKABLE bool refresh(bool noAur = false);
  Q_INVOKABLE bool sync();

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
  int     m_updatesCount    = 0;
  int     m_aurUpdatesCount = 0;
  QString m_updatesText;
  QString m_aurUpdatesText;
  QString m_lastChecked;
  QString m_error;
};
