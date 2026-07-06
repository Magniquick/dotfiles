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
      index.row() >= m_blockCount) {
    return {};
  }
  // TODO(stage2): map the role to the per-block field once Rust reports rows.
  switch (role) {
    case BlockIdRole:
    case KindRole:
    case TypeRole:
    case ContentRole:
    case RawRole:
    case DisplayRole:
    case CompletedRole:
    case LanguageRole:
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

  // Re-parse and reset the model, then update the derived block count.
  beginResetModel();
  const int blockCount =
      QsNative_MarkdownStream_SetContent(m_handle, m_content.toUtf8().constData());
  endResetModel();
  syncBlockCount(blockCount);
}

void QsNativeMarkdownStream::setStreaming(bool value) {
  if (value == m_streaming) {
    return;
  }
  m_streaming = value;
  emit streamingChanged();

  beginResetModel();
  const int blockCount = QsNative_MarkdownStream_SetStreaming(m_handle, m_streaming);
  endResetModel();
  syncBlockCount(blockCount);
}

void QsNativeMarkdownStream::finalize() {
  beginResetModel();
  const int blockCount = QsNative_MarkdownStream_Finalize(m_handle);
  endResetModel();
  syncBlockCount(blockCount);
}

void QsNativeMarkdownStream::syncBlockCount(int blockCount) {
  if (blockCount != m_blockCount) {
    m_blockCount = blockCount;
    emit blockCountChanged();
  }
}
