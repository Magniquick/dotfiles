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
  int rowCount(const QModelIndex& parent = {}) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  // Properties
  QString modelId() const {
    return m_modelId;
  }
  QVariantList commands() const;

  QString systemPrompt() const {
    return m_systemPrompt;
  }
  QVariantMap providerConfig() const {
    return m_providerConfig;
  }
  QVariantList mcpConfig() const {
    return m_mcpConfig;
  }
  bool busy() const {
    return m_busy;
  }
  QString status() const {
    return m_status;
  }
  QString error() const {
    return m_error;
  }
  QVariantList mcpServers() const {
    return m_mcpServers;
  }
  QVariantList mcpTools() const {
    return m_mcpTools;
  }
  QVariantList mcpPrompts() const {
    return m_mcpPrompts;
  }
  QVariantList mcpResources() const {
    return m_mcpResources;
  }
  QString mcpStatus() const {
    return m_mcpStatus;
  }
  QString mcpError() const {
    return m_mcpError;
  }
  QVariantList resumeConversations() const {
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
  Q_INVOKABLE QString copyAllText() const;
  Q_INVOKABLE QVariantList pasteImageFromClipboard();
  Q_INVOKABLE QVariantList pasteAttachmentFromClipboard();
  Q_INVOKABLE bool restoreHistory();
  Q_INVOKABLE bool refreshMcp();
  Q_INVOKABLE QVariantMap getMcpPrompt(const QString& serverId, const QString& promptName,
                                       const QVariantMap& arguments = QVariantMap{});
  Q_INVOKABLE QVariantMap readMcpResource(const QString& serverId, const QString& uri);
  Q_INVOKABLE bool refreshResumeConversations(const QString& query = QString());
  Q_INVOKABLE bool resumeConversation(const QString& conversationId);

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
  bool ensureHistoryConversation();
  bool createHistoryConversation();
  bool resumeHistoryConversation(const QString& conversationId = QString());
  bool closeHistoryConversation();
  QVariantMap applyHistoryAction(const QVariantMap& action) const;
  QVariantMap messageToHistoryMap(const Message& msg, int ordinal,
                                  const QString& statusOverride = QString(),
                                  const QString& completedAt = QString()) const;
  void persistMessageAt(int row, const QString& statusOverride = QString(),
                        const QString& completedAt = QString());
  void persistToolCallAt(int row);
  void persistResponseItems(const QJsonArray& items, const QString& source);
  void persistDeletedFromOrdinal(int ordinal);
  QVariantMap extraForMessage(const Message& msg) const;
  QVariantMap metricsForMessage(const Message& msg) const;
  QString utcNow() const;
  void restoreMessages(const QVariantList& messages);
  void restoreReplayItems();
  QString buildHistoryJson() const;
  QByteArray buildProviderConfigJson() const;
  QByteArray buildMcpConfigJson() const;
  void refreshMcpStateAsync();
  QString activeProviderId() const;
  QVariantMap activeProviderConfig() const;
  QVariantMap resumeOptionFromSummary(const QVariantMap& summary) const;
  int indexOfMessage(const QString& id) const;
  int indexOfToolCall(const QString& toolCallId) const;
  int lastAssistantChatIndex() const;
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
