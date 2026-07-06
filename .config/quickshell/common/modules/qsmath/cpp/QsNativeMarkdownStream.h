#pragma once

#include <QAbstractListModel>
#include <QByteArray>
#include <QHash>
#include <QString>
#include <QVariant>

struct MarkdownStreamHandle;

// Streaming markdown block model, registered in QML as `MarkdownStreamModel`.
//
// STAGE-1 STUB: preserves the full QML-facing surface (writable `content` /
// `streaming`, read-only `blockCount`, the three QAbstractListModel overrides,
// and `finalize()`) but the Rust core is a no-op, so the model always reports
// zero rows. TODO(stage2): the Rust side will re-parse content into blocks.
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
  void syncBlockCount(int blockCount);

  MarkdownStreamHandle* m_handle;

  QString m_content;
  bool m_streaming = true;
  int m_blockCount = 0;
};
