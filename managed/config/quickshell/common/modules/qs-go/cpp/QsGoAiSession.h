#pragma once
#include <QAbstractListModel>
#include <QColor>
#include <QJsonObject>
#include <QList>
#include <QString>
#include <QUuid>
#include <QVariantList>
#include <QVariantMap>

class QsGoAiSession : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(QString model_id READ modelId WRITE setModelId NOTIFY modelIdChanged)
  Q_PROPERTY(
      QString system_prompt READ systemPrompt WRITE setSystemPrompt NOTIFY systemPromptChanged)
  Q_PROPERTY(QVariantMap provider_config READ providerConfig WRITE setProviderConfig NOTIFY
                 providerConfigChanged)
  Q_PROPERTY(QVariantList mcp_config READ mcpConfig WRITE setMcpConfig NOTIFY mcpConfigChanged)
  Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
  Q_PROPERTY(QString status READ status NOTIFY statusChanged)
  Q_PROPERTY(QString error READ error NOTIFY errorChanged)
  Q_PROPERTY(QVariantList commands READ commands CONSTANT)
  Q_PROPERTY(QVariantList mcp_servers READ mcpServers NOTIFY mcpStateChanged)
  Q_PROPERTY(QVariantList mcp_tools READ mcpTools NOTIFY mcpStateChanged)
  Q_PROPERTY(QVariantList mcp_prompts READ mcpPrompts NOTIFY mcpStateChanged)
  Q_PROPERTY(QVariantList mcp_resources READ mcpResources NOTIFY mcpStateChanged)
  Q_PROPERTY(QString mcp_status READ mcpStatus NOTIFY mcpStateChanged)
  Q_PROPERTY(QString mcp_error READ mcpError NOTIFY mcpStateChanged)
  Q_PROPERTY(
      QVariantList resume_conversations READ resumeConversations NOTIFY resumeConversationsChanged)

public:
  struct Message {
    QString id;
    QString sender; // "user" | "assistant"
    QString body;
    QString kind; // "chat" | "info"
    QVariantMap metrics;
    QVariantList attachments;
    QVariantMap tool;
    bool showHeader = true;
  };

  struct ReplayItem {
    QString id;
    QString turnId;
    int turnOrdinal = 0;
    int itemOrdinal = 0;
    QString source;
    QString itemType;
    QString callId;
    QJsonObject raw;
  };

  enum Roles {
    IdRole = Qt::UserRole + 1,
    SenderRole,
    BodyRole,
    KindRole,
    MetricsRole,
    AttachmentsRole,
    ToolRole,
    ShowHeaderRole
  };

  explicit QsGoAiSession(QObject* parent = nullptr);

  // QAbstractListModel
  [[nodiscard]] auto rowCount(const QModelIndex& parent = {}) const -> int override;
  [[nodiscard]] auto data(const QModelIndex& index, int role = Qt::DisplayRole) const
      -> QVariant override;
  [[nodiscard]] auto roleNames() const -> QHash<int, QByteArray> override;

  // Properties
  [[nodiscard]] auto modelId() const -> QString {
    return m_modelId;
  }
  [[nodiscard]] static auto commands() -> QVariantList;

  [[nodiscard]] auto systemPrompt() const -> QString {
    return m_systemPrompt;
  }
  [[nodiscard]] auto providerConfig() const -> QVariantMap {
    return m_providerConfig;
  }
  [[nodiscard]] auto mcpConfig() const -> QVariantList {
    return m_mcpConfig;
  }
  [[nodiscard]] auto busy() const -> bool {
    return m_busy;
  }
  [[nodiscard]] auto status() const -> QString {
    return m_status;
  }
  [[nodiscard]] auto error() const -> QString {
    return m_error;
  }
  [[nodiscard]] auto mcpServers() const -> QVariantList {
    return m_mcpServers;
  }
  [[nodiscard]] auto mcpTools() const -> QVariantList {
    return m_mcpTools;
  }
  [[nodiscard]] auto mcpPrompts() const -> QVariantList {
    return m_mcpPrompts;
  }
  [[nodiscard]] auto mcpResources() const -> QVariantList {
    return m_mcpResources;
  }
  [[nodiscard]] auto mcpStatus() const -> QString {
    return m_mcpStatus;
  }
  [[nodiscard]] auto mcpError() const -> QString {
    return m_mcpError;
  }
  [[nodiscard]] auto resumeConversations() const -> QVariantList {
    return m_resumeConversations;
  }

  void setModelId(const QString& v);
  void setSystemPrompt(const QString& v);
  void setProviderConfig(const QVariantMap& v);
  void setMcpConfig(const QVariantList& v);

  // Invokables (matching Rust interface)
  Q_INVOKABLE static void setAppLinkColor(const QColor& color);
  Q_INVOKABLE void submitInput(const QString& text);
  Q_INVOKABLE void submitInputWithAttachments(const QString& text, const QVariantList& attachments);
  Q_INVOKABLE void cancel();
  Q_INVOKABLE void regenerate(const QString& messageId);
  Q_INVOKABLE void deleteMessage(const QString& messageId);
  Q_INVOKABLE void editMessage(const QString& messageId, const QString& newBody);
  Q_INVOKABLE void resetForModelSwitch(const QString& newModelId);
  Q_INVOKABLE void appendInfo(const QString& text);
  Q_INVOKABLE [[nodiscard]] auto copyAllText() const -> QString;
  Q_INVOKABLE static auto pasteImageFromClipboard() -> QVariantList;
  Q_INVOKABLE static auto pasteAttachmentFromClipboard() -> QVariantList;
  Q_INVOKABLE auto restoreHistory() -> bool;
  Q_INVOKABLE auto refreshMcp() -> bool;
  Q_INVOKABLE auto getMcpPrompt(const QString& serverId, const QString& promptName,
                                const QVariantMap& arguments = QVariantMap{}) -> QVariantMap;
  Q_INVOKABLE auto readMcpResource(const QString& serverId, const QString& uri) -> QVariantMap;
  Q_INVOKABLE auto refreshResumeConversations(const QString& query = QString()) -> bool;
  Q_INVOKABLE auto resumeConversation(const QString& conversationId) -> bool;

signals:
  void modelIdChanged();
  void systemPromptChanged();
  void providerConfigChanged();
  void mcpConfigChanged();
  void busyChanged();
  void statusChanged();
  void errorChanged();
  void mcpStateChanged();

  void openModelPickerRequested();
  void openMoodPickerRequested();
  void openResumePickerRequested();
  void openMcpAddRequested();
  void scrollToEndRequested();
  void copyAllRequested(const QString& text);
  void streamDone();
  void resumeConversationsChanged();

private:
  static void tokenCallback(void* ctx, const char* token, int done);
  void startStream(const QString& text, const QVariantList& attachments);
  auto ensureHistoryConversation() -> bool;
  auto createHistoryConversation() -> bool;
  auto resumeHistoryConversation(const QString& conversationId = QString()) -> bool;
  auto closeHistoryConversation() -> bool;
  [[nodiscard]] static auto applyHistoryAction(const QVariantMap& action) -> QVariantMap;
  [[nodiscard]] auto messageToHistoryMap(const Message& msg, int ordinal,
                                         const QString& statusOverride = QString(),
                                         const QString& completedAt = QString()) const
      -> QVariantMap;
  void persistMessageAt(int row, const QString& statusOverride = QString(),
                        const QString& completedAt = QString());
  void persistToolCallAt(int row);
  void persistResponseItems(const QJsonArray& items, const QString& source);
  void persistDeletedFromOrdinal(int ordinal);
  [[nodiscard]] static auto extraForMessage(const Message& msg) -> QVariantMap;
  [[nodiscard]] static auto metricsForMessage(const Message& msg) -> QVariantMap;
  [[nodiscard]] static auto utcNow() -> QString;
  void restoreMessages(const QVariantList& messages);
  void restoreReplayItems();
  [[nodiscard]] auto buildHistoryJson() const -> QString;
  [[nodiscard]] auto buildProviderConfigJson() const -> QByteArray;
  [[nodiscard]] auto buildMcpConfigJson() const -> QByteArray;
  void refreshMcpStateAsync();
  [[nodiscard]] auto activeProviderId() const -> QString;
  [[nodiscard]] auto activeProviderConfig() const -> QVariantMap;
  [[nodiscard]] static auto resumeOptionFromSummary(const QVariantMap& summary) -> QVariantMap;
  [[nodiscard]] auto indexOfMessage(const QString& id) const -> int;
  [[nodiscard]] auto indexOfToolCall(const QString& toolCallId) const -> int;
  [[nodiscard]] auto lastAssistantChatIndex() const -> int;
  void handleToolEventJson(const QString& json);
  void setBusy(bool v);
  void setStatus(const QString& v);
  void setError(const QString& v);
  void handleSlashCommand(const QString& cmd);

  QList<Message> m_messages;
  QList<ReplayItem> m_replayItems;
  int m_sessionId = -1;
  QString m_conversationId;
  QString m_currentTurnId;
  int m_currentTurnOrdinal = -1;
  int m_nextReplayItemOrdinal = 0;
  bool m_historyLoaded = false;
  bool m_restoringHistory = false;

  QString m_modelId;
  QString m_systemPrompt;
  QVariantMap m_providerConfig;
  QVariantList m_mcpConfig;
  bool m_busy = false;
  QString m_status;
  QString m_error;
  QVariantList m_mcpServers;
  QVariantList m_mcpTools;
  QVariantList m_mcpPrompts;
  QVariantList m_mcpResources;
  QString m_mcpStatus;
  QString m_mcpError;
  QVariantList m_resumeConversations;
};
