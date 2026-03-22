#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- Callback types ---------- */

/* token callback: done=0 normal token, done=1 success/done, done=-1 error */
typedef void (*QsGo_TokenFn)   (void* ctx, const char* token, int done);
/* backlight change callback */
typedef void (*QsGo_BrightFn)  (void* ctx, int percent, const char* device);

/* ---------- SysInfo ---------- */

/* Returns malloc'd JSON; caller must free with QsGo_Free(). */
char* QsGo_SysInfo_Refresh(const char* diskDevice);

/* ---------- Backlight ---------- */

char* QsGo_Backlight_Get(void);
char* QsGo_Backlight_Set(int percent);

/* Returns session id. Calls cb from a background goroutine on change. */
int   QsGo_Backlight_Monitor(QsGo_BrightFn cb, void* ctx);
void  QsGo_Backlight_StopMonitor(int id);

/* ---------- Pacman ---------- */

char* QsGo_Pacman_Refresh(int noAur);
char* QsGo_Pacman_Sync(void);

/* ---------- iCal ---------- */

char* QsGo_Ical_Refresh(const char* envFile, int days);

/* ---------- AI models ---------- */

	char* QsGo_AiModels_Refresh(const char* providerConfigJSON);
char* QsGo_AiMcp_Refresh(const char* configJSON);
char* QsGo_AiMcp_GetPrompt(const char* configJSON, const char* serverID, const char* promptName, const char* argsJSON);
char* QsGo_AiMcp_ReadResource(const char* configJSON, const char* serverID, const char* uri);

/* ---------- AI chat ---------- */

/* Starts a streaming session; returns session id. */
int   QsGo_AiChat_Stream(const char* modelID,
	                          const char* providerConfigJSON,
                          const char* mcpConfigJSON,
	                          const char* systemPrompt,
	                          const char* historyJSON,
	                          const char* message,
                          const char* attachmentsJSON,
                          QsGo_TokenFn cb,
                          void* ctx);

void  QsGo_AiChat_Cancel(int id);
char* QsGo_AiChat_LastMetrics();

/* ---------- Todoist ---------- */

char* QsGo_Todoist_List(const char* envFile, const char* cachePath, int preferCache);
char* QsGo_Todoist_Action(const char* envFile, const char* verb, const char* argsJSON);

/* ---------- Memory ---------- */

/* Free a string returned by any QsGo_* function. */
void  QsGo_Free(char* s);

#ifdef __cplusplus
} // extern "C"
#endif
