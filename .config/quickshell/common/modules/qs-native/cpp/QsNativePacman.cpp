#include "QsNativePacman.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

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

void QsNativePacman::snapshotCallback(void* ctx, const PacmanSnapshotC* snap) {
  auto* self = static_cast<QsNativePacman*>(ctx);
  if (snap == nullptr) {
    return;
  }

  // Deep-copy synchronously: the char* fields (row-level and aggregate) are
  // only valid for the duration of this call.
  QList<UpdateItem> items;
  items.reserve(static_cast<qsizetype>(snap->items_len));
  for (size_t i = 0; i < snap->items_len; ++i) {
    const UpdateItemC& row = snap->items[i];
    items.append(UpdateItem{
        QString::fromUtf8(row.name),
        QString::fromUtf8(row.old_version),
        QString::fromUtf8(row.new_version),
        QString::fromUtf8(row.source),
    });
  }

  const int updatesCount = snap->updates_count;
  const int aurUpdatesCount = snap->aur_updates_count;
  const QString updatesText = QString::fromUtf8(snap->updates_text);
  const QString aurUpdatesText = QString::fromUtf8(snap->aur_updates_text);
  const QString lastChecked = QString::fromUtf8(snap->last_checked);
  const QString error = QString::fromUtf8(snap->error);

  qsn::postToObject(self, [self, items, updatesCount, aurUpdatesCount, updatesText,
                            aurUpdatesText, lastChecked, error]() {
    self->applySnapshot(items, updatesCount, aurUpdatesCount, updatesText, aurUpdatesText,
                        lastChecked, error);
  });
}

void QsNativePacman::applySnapshot(const QList<UpdateItem>& items, int updatesCount,
                                    int aurUpdatesCount, const QString& updatesText,
                                    const QString& aurUpdatesText, const QString& lastChecked,
                                    const QString& error) {
  beginResetModel();
  m_items = items;
  endResetModel();

  const int itemsCount = static_cast<int>(m_items.size());
  const bool hasUpdates = itemsCount > 0;

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
