#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- Callback types ---------- */

/* token callback: done=0 normal token, done=1 success/done, done=2 event JSON, done=-1 error */
using QsGo_TokenFn = void (*)(void* ctx, const char* token, int done);

/* ---------- SysInfo ---------- */

auto QsGo_SysStats_Snapshot(void) -> char*;
auto QsGo_SysStats_NetDev(const char* iface) -> char*;

/* ---------- Pacman ---------- */

auto QsGo_Pacman_Refresh(int noAur) -> char*;
auto QsGo_Pacman_Sync(void) -> char*;

/* ---------- iCal ---------- */

auto QsGo_Ical_Refresh(int days) -> char*;

/* ---------- systemd failed units ---------- */

auto QsGo_SystemdFailed_Refresh(void) -> char*;

/* ---------- Config / secrets resolver ---------- */

auto QsGo_Config_Resolve(void) -> char*;

auto QsGo_AiMcp_Refresh(const char* configJSON) -> char*;
auto QsGo_AiMcp_GetPrompt(const char* configJSON, const char* serverID, const char* promptName,
                          const char* argsJSON) -> char*;
auto QsGo_AiMcp_ReadResource(const char* configJSON, const char* serverID, const char* uri)
    -> char*;

/* ---------- AI chat ---------- */

/* Starts a streaming session; returns session id. */
auto QsGo_AiChat_Stream(const char* modelID, const char* providerConfigJSON,
                        const char* mcpConfigJSON, const char* systemPrompt,
                        const char* historyJSON, const char* message, const char* attachmentsJSON,
                        QsGo_TokenFn cb, void* ctx) -> int;

void QsGo_AiChat_Cancel(int id);
auto QsGo_AiChat_LastMetrics() -> char*;
auto QsGo_AiHistory_Apply(const char* actionJSON) -> char*;

/* ---------- Todoist ---------- */

auto QsGo_Todoist_List(const char* cachePath, int preferCache) -> char*;
auto QsGo_Todoist_Action(const char* verb, const char* argsJSON) -> char*;

/* ---------- Memory ---------- */

/* Free a string returned by any QsGo_* function. */
void QsGo_Free(char* s);

#ifdef __cplusplus
} // extern "C"
#endif
