#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QString>
#include <QVariant>
#include <QVector>

struct MarkdownStreamHandle;
struct MarkdownRowC;

// Streaming markdown block model, registered in QML as `MarkdownStreamModel`.
//
// The Rust `mdstream`-backed core re-parses `content` on every call and
// delivers the *current full row snapshot* synchronously (no worker thread;
// parsing is pure CPU work). This QObject diffs that snapshot against its own
// cached rows: if committed block ids still form a stable prefix, it grows
// the model incrementally (`beginInsertRows` for newly-committed rows,
// `dataChanged` for the last row if its content changed) instead of a full
// reset, so QML delegates for already-committed blocks are never recreated.
// A prefix mismatch (non-append edit) falls back to `beginResetModel`.
class QsNativeMarkdownStream : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(QString content READ content WRITE setContent NOTIFY contentChanged)
  Q_PROPERTY(bool streaming READ streaming WRITE setStreaming NOTIFY streamingChanged)
  Q_PROPERTY(int blockCount READ blockCount NOTIFY blockCountChanged)

public:
  enum Roles {
    BlockIdRole = 0x0100,
    KindRole = 0x0101,
    TypeRole = 0x0102,
    ContentRole = 0x0103,
    RawRole = 0x0104,
    DisplayRole = 0x0105,
    CompletedRole = 0x0106,
    LanguageRole = 0x0107,
  };

  explicit QsNativeMarkdownStream(QObject* parent = nullptr);
  ~QsNativeMarkdownStream() override;

  // QAbstractListModel
  [[nodiscard]] auto rowCount(const QModelIndex& parent = {}) const -> int override;
  [[nodiscard]] auto data(const QModelIndex& index, int role = Qt::DisplayRole) const
      -> QVariant override;
  [[nodiscard]] auto roleNames() const -> QHash<int, QByteArray> override;

  // Properties
  [[nodiscard]] auto content() const -> QString { return m_content; }
  [[nodiscard]] auto streaming() const -> bool { return m_streaming; }
  [[nodiscard]] auto blockCount() const -> int { return m_blockCount; }

  void setContent(const QString& value);
  void setStreaming(bool value);

  Q_INVOKABLE void finalize();

signals:
  void contentChanged();
  void streamingChanged();
  void blockCountChanged();

private:
  struct Row {
    quint64 blockId = 0;
    QString kind;
    QString type;
    QString content;
    QString raw;
    QString display;
    bool completed = false;
    QString language;

    auto operator==(const Row& other) const -> bool = default;
  };

  static void rowsCallback(void* ctx, const MarkdownRowC* rows, size_t len);
  void applyRows(const QVector<Row>& newRows);
  void syncBlockCount();

  MarkdownStreamHandle* m_handle;

  QString m_content;
  bool m_streaming = true;
  int m_blockCount = 0;
  QVector<Row> m_rows;
};
