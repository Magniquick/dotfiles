#pragma once
#include <QObject>

class QsGoAiModels : public QObject {
  Q_OBJECT

  Q_PROPERTY(QString models_json     READ modelsJson     NOTIFY modelsJsonChanged)
  Q_PROPERTY(bool    busy            READ busy           NOTIFY busyChanged)
  Q_PROPERTY(QString status          READ status         NOTIFY statusChanged)
  Q_PROPERTY(QString error           READ error          NOTIFY errorChanged)
  Q_PROPERTY(QString openai_api_key  READ openaiApiKey   WRITE setOpenaiApiKey  NOTIFY openaiApiKeyChanged)
  Q_PROPERTY(QString gemini_api_key  READ geminiApiKey   WRITE setGeminiApiKey  NOTIFY geminiApiKeyChanged)
  Q_PROPERTY(QString openai_base_url READ openaiBaseUrl  WRITE setOpenaiBaseUrl NOTIFY openaiBaseUrlChanged)

public:
  explicit QsGoAiModels(QObject* parent = nullptr);

  QString modelsJson()   const { return m_modelsJson; }
  bool    busy()         const { return m_busy; }
  QString status()       const { return m_status; }
  QString error()        const { return m_error; }
  QString openaiApiKey() const { return m_openaiApiKey; }
  QString geminiApiKey() const { return m_geminiApiKey; }
  QString openaiBaseUrl() const { return m_openaiBaseUrl; }

  void setOpenaiApiKey(const QString& v);
  void setGeminiApiKey(const QString& v);
  void setOpenaiBaseUrl(const QString& v);

  Q_INVOKABLE bool refresh();

signals:
  void modelsJsonChanged();
  void busyChanged();
  void statusChanged();
  void errorChanged();
  void openaiApiKeyChanged();
  void geminiApiKeyChanged();
  void openaiBaseUrlChanged();

private:
  QString m_modelsJson;
  bool    m_busy = false;
  QString m_status;
  QString m_error;
  QString m_openaiApiKey;
  QString m_geminiApiKey;
  QString m_openaiBaseUrl;
};
