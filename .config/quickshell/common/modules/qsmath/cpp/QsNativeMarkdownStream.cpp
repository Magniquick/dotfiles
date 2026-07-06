#include "QsNativeMarkdownStream.h"
#include "qsmath_api.h"

QsNativeMarkdownStream::QsNativeMarkdownStream(QObject* parent)
    : QAbstractListModel(parent), m_handle(QsNative_MarkdownStream_New()) {}

QsNativeMarkdownStream::~QsNativeMarkdownStream() {
  QsNative_MarkdownStream_Delete(m_handle);
}

auto QsNativeMarkdownStream::rowCount(const QModelIndex& parent) const -> int {
  if (parent.isValid()) {
    return 0;
  }
  return m_blockCount;
}

auto QsNativeMarkdownStream::data(const QModelIndex& index, int role) const -> QVariant {
  if (!index.isValid() || index.column() != 0 || index.row() < 0 ||
      index.row() >= m_rows.size()) {
    return {};
  }
  const Row& row = m_rows.at(index.row());
  switch (role) {
    case BlockIdRole:
      // Matches the original i32-narrowed role value the QML side expects.
      return static_cast<qint32>(row.blockId);
    case KindRole:
      return row.kind;
    case TypeRole:
      return row.type;
    case ContentRole:
      return row.content;
    case RawRole:
      return row.raw;
    case DisplayRole:
      return row.display;
    case CompletedRole:
      return row.completed;
    case LanguageRole:
      return row.language;
    default:
      return {};
  }
}

auto QsNativeMarkdownStream::roleNames() const -> QHash<int, QByteArray> {
  return {
      {BlockIdRole, "blockId"}, {KindRole, "kind"},         {TypeRole, "type"},
      {ContentRole, "content"}, {RawRole, "raw"},           {DisplayRole, "display"},
      {CompletedRole, "completed"}, {LanguageRole, "language"},
  };
}

void QsNativeMarkdownStream::setContent(const QString& value) {
  if (value == m_content) {
    return;
  }
  m_content = value;
  emit contentChanged();

  QVector<Row> newRows;
  QsNative_MarkdownStream_SetContent(m_handle, m_content.toUtf8().constData(), &newRows,
                                     &QsNativeMarkdownStream::rowsCallback);
  applyRows(newRows);
}

void QsNativeMarkdownStream::setStreaming(bool value) {
  if (value == m_streaming) {
    return;
  }
  m_streaming = value;
  emit streamingChanged();

  QVector<Row> newRows;
  QsNative_MarkdownStream_SetStreaming(m_handle, m_streaming, &newRows,
                                       &QsNativeMarkdownStream::rowsCallback);
  applyRows(newRows);
}

void QsNativeMarkdownStream::finalize() {
  QVector<Row> newRows;
  QsNative_MarkdownStream_Finalize(m_handle, &newRows, &QsNativeMarkdownStream::rowsCallback);
  applyRows(newRows);
}

void QsNativeMarkdownStream::rowsCallback(void* ctx, const MarkdownRowC* rows, size_t len) {
  // Deep-copy synchronously: the char* fields are only valid for this call.
  // Called directly (no worker thread involved), so it's safe to write
  // straight into the caller's stack-local QVector.
  auto* out = static_cast<QVector<Row>*>(ctx);
  out->reserve(static_cast<qsizetype>(len));
  for (size_t i = 0; i < len; ++i) {
    const MarkdownRowC& src = rows[i];
    out->append(Row{
        .blockId = src.block_id,
        .kind = QString::fromUtf8(src.kind),
        .type = QString::fromUtf8(src.block_type),
        .content = QString::fromUtf8(src.content),
        .raw = QString::fromUtf8(src.raw),
        .display = QString::fromUtf8(src.display),
        .completed = src.completed,
        .language = QString::fromUtf8(src.language),
    });
  }
}

void QsNativeMarkdownStream::applyRows(const QVector<Row>& newRows) {
  const qsizetype oldCount = m_rows.size();
  const qsizetype newCount = newRows.size();

  // Committed block ids are stable across delta-appends, so the common
  // prefix (by id) tells us whether this was a pure append or a reset.
  qsizetype commonPrefix = 0;
  while (commonPrefix < oldCount && commonPrefix < newCount &&
         m_rows.at(commonPrefix).blockId == newRows.at(commonPrefix).blockId) {
    ++commonPrefix;
  }

  if (commonPrefix < oldCount) {
    // A previously-committed block no longer matches: the stream was reset
    // (non-append edit), so recreate every row/delegate.
    beginResetModel();
    m_rows = newRows;
    endResetModel();
  } else {
    // Every existing row survived at the same id; only the last row's
    // content may have changed (pending -> pending or pending -> committed),
    // and any rows beyond the old count are newly appended.
    if (commonPrefix > 0) {
      const qsizetype lastIdx = commonPrefix - 1;
      if (m_rows.at(lastIdx) != newRows.at(lastIdx)) {
        m_rows[lastIdx] = newRows.at(lastIdx);
        const QModelIndex mi = index(static_cast<int>(lastIdx));
        emit dataChanged(mi, mi);
      }
    }
    if (newCount > oldCount) {
      beginInsertRows({}, static_cast<int>(oldCount), static_cast<int>(newCount) - 1);
      for (qsizetype i = oldCount; i < newCount; ++i) {
        m_rows.append(newRows.at(i));
      }
      endInsertRows();
    }
  }

  syncBlockCount();
}

void QsNativeMarkdownStream::syncBlockCount() {
  const int blockCount = static_cast<int>(m_rows.size());
  if (blockCount != m_blockCount) {
    m_blockCount = blockCount;
    emit blockCountChanged();
  }
}
