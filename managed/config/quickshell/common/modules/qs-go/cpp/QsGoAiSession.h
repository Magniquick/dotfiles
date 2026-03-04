#pragma once
#include <QAbstractListModel>
#include <QColor>
#include <QList>
#include <QString>
#include <QUuid>

class QsGoAiSession : public QAbstractListModel {
  Q_OBJECT

  Q_PROPERTY(QString model_id        READ modelId        WRITE setModelId        NOTIFY modelIdChanged)
  Q_PROPERTY(QString system_prompt   READ systemPrompt   WRITE setSystemPrompt   NOTIFY systemPromptChanged)
  Q_PROPERTY(QString openai_api_key  READ openaiApiKey   WRITE setOpenaiApiKey   NOTIFY openaiApiKeyChanged)
  Q_PROPERTY(QString gemini_api_key  READ geminiApiKey   WRITE setGeminiApiKey   NOTIFY geminiApiKeyChanged)
  Q_PROPERTY(QString openai_base_url READ openaiBaseUrl  WRITE setOpenaiBaseUrl  NOTIFY openaiBaseUrlChanged)
  Q_PROPERTY(bool    busy            READ busy           NOTIFY busyChanged)
  Q_PROPERTY(QString status          READ status         NOTIFY statusChanged)
  Q_PROPERTY(QString error           READ error          NOTIFY errorChanged)
  Q_PROPERTY(QString commandsJson    READ commandsJson   CONSTANT)

public:
  struct Message {
    QString id;
    QString sender;      // "user" | "assistant"
    QString body;
    QString kind;        // "chat" | "info"
    QString metrics;
    QString attachments;
  };

  enum Roles {
    IdRole          = Qt::UserRole + 1,
    SenderRole,
    BodyRole,
    KindRole,
    MetricsRole,
    AttachmentsRole
  };

  explicit QsGoAiSession(QObject* parent = nullptr);

  // QAbstractListModel
  int rowCount(const QModelIndex& parent = {}) const override;
  QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
  QHash<int, QByteArray> roleNames() const override;

  // Properties
  QString modelId()       const { return m_modelId; }
  QString commandsJson()  const;

  QString systemPrompt()  const { return m_systemPrompt; }
  QString openaiApiKey()  const { return m_openaiApiKey; }
  QString geminiApiKey()  const { return m_geminiApiKey; }
  QString openaiBaseUrl() const { return m_openaiBaseUrl; }
  bool    busy()          const { return m_busy; }
  QString status()        const { return m_status; }
  QString error()         const { return m_error; }

  void setModelId(const QString& v);
  void setSystemPrompt(const QString& v);
  void setOpenaiApiKey(const QString& v);
  void setGeminiApiKey(const QString& v);
  void setOpenaiBaseUrl(const QString& v);

  // Invokables (matching Rust interface)
  Q_INVOKABLE static void setAppLinkColor(const QColor& color);
  Q_INVOKABLE void   submitInput(const QString& text);
  Q_INVOKABLE void   submitInputWithAttachments(const QString& text, const QString& attachmentsJson);
  Q_INVOKABLE void   cancel();
  Q_INVOKABLE void   regenerate(const QString& messageId);
  Q_INVOKABLE void   deleteMessage(const QString& messageId);
  Q_INVOKABLE void   editMessage(const QString& messageId, const QString& newBody);
  Q_INVOKABLE void   resetForModelSwitch(const QString& newModelId);
  Q_INVOKABLE void   appendInfo(const QString& text);
  Q_INVOKABLE QString copyAllText() const;
  Q_INVOKABLE QString pasteImageFromClipboard();
  Q_INVOKABLE QString pasteAttachmentFromClipboard();

signals:
  void modelIdChanged();
  void systemPromptChanged();
  void openaiApiKeyChanged();
  void geminiApiKeyChanged();
  void openaiBaseUrlChanged();
  void busyChanged();
  void statusChanged();
  void errorChanged();

  void openModelPickerRequested();
  void openMoodPickerRequested();
  void scrollToEndRequested();
  void copyAllRequested(const QString& text);
  void streamDone();

private:
  static void tokenCallback(void* ctx, const char* token, int done);
  void startStream(const QString& text, const QString& attachmentsJson);
  QString buildHistoryJson() const;
  int     indexOfMessage(const QString& id) const;
  void    setBusy(bool v);
  void    setStatus(const QString& v);
  void    setError(const QString& v);
  void    handleSlashCommand(const QString& cmd);

  QList<Message> m_messages;
  int            m_sessionId = -1;

  QString m_modelId;
  QString m_systemPrompt;
  QString m_openaiApiKey;
  QString m_geminiApiKey;
  QString m_openaiBaseUrl;
  bool    m_busy   = false;
  QString m_status;
  QString m_error;
};
