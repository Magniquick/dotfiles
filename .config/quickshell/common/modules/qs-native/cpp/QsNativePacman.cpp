#include "QsNativePacman.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

QsNativePacman::QsNativePacman(QObject* parent)
    : QAbstractListModel(parent), m_handle(QsNative_Pacman_New()) {}

QsNativePacman::~QsNativePacman() {
  QsNative_Pacman_Delete(m_handle);
}

auto QsNativePacman::rowCount(const QModelIndex& parent) const -> int {
  if (parent.isValid()) {
    return 0;
  }
  return static_cast<int>(m_items.size());
}

auto QsNativePacman::data(const QModelIndex& index, int role) const -> QVariant {
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

auto QsNativePacman::roleNames() const -> QHash<int, QByteArray> {
  return {
      {NameRole, "name"},
      {OldVersionRole, "old_version"},
      {NewVersionRole, "new_version"},
      {SourceRole, "source"},
  };
}

auto QsNativePacman::refresh(bool no_aur) -> bool {
  QsNative_Pacman_Refresh(m_handle, no_aur, this, &QsNativePacman::snapshotCallback);
  return true;
}

auto QsNativePacman::sync() -> bool {
  QsNative_Pacman_Sync(m_handle);
  return true;
}

void QsNativePacman::snapshotCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativePacman*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applySnapshot(payload); });
}

void QsNativePacman::applySnapshot(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    return;
  }
  const QJsonObject o = doc.object();

  QList<UpdateItem> items;
  const QJsonArray rawItems = o.value(QStringLiteral("items")).toArray();
  items.reserve(static_cast<qsizetype>(rawItems.size()));
  for (const QJsonValue& value : rawItems) {
    const QJsonObject row = value.toObject();
    items.append(UpdateItem{
        row.value(QStringLiteral("name")).toString(),
        row.value(QStringLiteral("old_version")).toString(),
        row.value(QStringLiteral("new_version")).toString(),
        row.value(QStringLiteral("source")).toString(),
    });
  }

  beginResetModel();
  m_items = std::move(items);
  endResetModel();

  const int updatesCount = o.value(QStringLiteral("updates_count")).toInt();
  const int aurUpdatesCount = o.value(QStringLiteral("aur_updates_count")).toInt();
  const int itemsCount = static_cast<int>(m_items.size());
  const QString updatesText = o.value(QStringLiteral("updates_text")).toString();
  const QString aurUpdatesText = o.value(QStringLiteral("aur_updates_text")).toString();
  const QString lastChecked = o.value(QStringLiteral("last_checked")).toString();
  const bool hasUpdates = itemsCount > 0;
  const QString error = o.value(QStringLiteral("error")).toString();

  if (updatesCount != m_updatesCount) {
    m_updatesCount = updatesCount;
    emit updates_countChanged();
  }
  if (aurUpdatesCount != m_aurUpdatesCount) {
    m_aurUpdatesCount = aurUpdatesCount;
    emit aur_updates_countChanged();
  }
  if (itemsCount != m_itemsCount) {
    m_itemsCount = itemsCount;
    emit items_countChanged();
  }
  if (updatesText != m_updatesText) {
    m_updatesText = updatesText;
    emit updates_textChanged();
  }
  if (aurUpdatesText != m_aurUpdatesText) {
    m_aurUpdatesText = aurUpdatesText;
    emit aur_updates_textChanged();
  }
  if (lastChecked != m_lastChecked) {
    m_lastChecked = lastChecked;
    emit last_checkedChanged();
  }
  if (hasUpdates != m_hasUpdates) {
    m_hasUpdates = hasUpdates;
    emit has_updatesChanged();
  }
  if (error != m_error) {
    m_error = error;
    emit errorChanged();
  }
}
