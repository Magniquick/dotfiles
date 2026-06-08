#include "QsGoPacman.h"
#include "qsgo_go_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QThreadPool>

QsGoPacman::QsGoPacman(QObject* parent) : QAbstractListModel(parent) {}

auto QsGoPacman::rowCount(const QModelIndex& parent) const -> int {
  if (parent.isValid()) {
    return 0;
  }
  return m_items.size();
}

auto QsGoPacman::data(const QModelIndex& index, int role) const -> QVariant {
  if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
    return {};
  }
  const UpdateItem& item = m_items.at(index.row());
  switch (role) {
    case NameRole:
      return item.name;
    case OldVersionRole:
      return item.oldVersion;
    case NewVersionRole:
      return item.newVersion;
    case SourceRole:
      return item.source;
    default:
      return {};
  }
}

auto QsGoPacman::roleNames() const -> QHash<int, QByteArray> {
  return {
      {NameRole, "name"},
      {OldVersionRole, "old_version"},
      {NewVersionRole, "new_version"},
      {SourceRole, "source"},
  };
}

auto QsGoPacman::refresh(bool noAur) -> bool {
  const int flag = noAur ? 1 : 0;
  QThreadPool::globalInstance()->start([this, flag]() -> void {
    char* raw = QsGo_Pacman_Refresh(flag);
    QByteArray const json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(
        this,
        [this, json]() -> void {
          const QJsonDocument doc = QJsonDocument::fromJson(json);
          if (!doc.isObject()) {
            return;
          }
          const QJsonObject obj = doc.object();

          // Rebuild model
          const QJsonArray arr = obj.value(QLatin1String("updates")).toArray();
          const int oldCount = m_items.size();
          const int newCount = arr.size();

          beginResetModel();
          m_items.clear();
          for (const QJsonValue& v : arr) {
            if (!v.isObject()) {
              continue;
            }
            const QJsonObject o = v.toObject();
            UpdateItem item;
            item.name = o.value(QLatin1String("name")).toString();
            item.oldVersion = o.value(QLatin1String("old_version")).toString();
            item.newVersion = o.value(QLatin1String("new_version")).toString();
            item.source = o.value(QLatin1String("source")).toString();
            m_items.append(item);
          }
          endResetModel();

#define SETPROP(member, sig, key, method)                                                          \
  {                                                                                                \
    auto v = obj.value(QLatin1String(key)).method;                                                 \
    if (v != (member)) {                                                                           \
      (member) = v;                                                                                \
      emit sig();                                                                                  \
    }                                                                                              \
  }

          SETPROP(m_updatesCount, updatesCountChanged, "updates_count", toInt())
          SETPROP(m_aurUpdatesCount, aurUpdatesCountChanged, "aur_updates_count", toInt()) {
            auto v = obj.value(QLatin1String("updates_text")).toString();
            if (v != m_updatesText) {
              m_updatesText = v;
              emit updatesTextChanged();
            }
          }
          {
            auto v = obj.value(QLatin1String("aur_updates_text")).toString();
            if (v != m_aurUpdatesText) {
              m_aurUpdatesText = v;
              emit aurUpdatesTextChanged();
            }
          }
          {
            auto v = obj.value(QLatin1String("last_checked")).toString();
            if (v != m_lastChecked) {
              m_lastChecked = v;
              emit lastCheckedChanged();
            }
          }
          {
            auto v = obj.value(QLatin1String("error")).toString();
            if (v != m_error) {
              m_error = v;
              emit errorChanged();
            }
          }
#undef SETPROP

          if (oldCount != newCount) {
            emit itemsCountChanged();
            emit hasUpdatesChanged();
          }
        },
        Qt::QueuedConnection);
  });
  return true;
}

auto QsGoPacman::sync() -> bool {
  QThreadPool::globalInstance()->start([]() -> void { QsGo_Free(QsGo_Pacman_Sync()); });
  return true;
}
