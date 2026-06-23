#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Rust-owned C ABI consumed by the C++ Qt bridge. */

/* token callback: done=0 normal token, done=1 success/done, done=2 event JSON, done=-1 error */
using QsNative_TokenFn = void (*)(void* ctx, const char* token, int done);

auto QsNative_AiMcp_Refresh() -> char*;

/* ---------- AI chat ---------- */

/* Starts a streaming session; returns session id. */
auto QsNative_AiChat_Stream(const char* modelID, const char* providerConfigJSON,
                            const char* systemPrompt, const char* conversationID,
                            const char* message, const char* attachmentsJSON, QsNative_TokenFn cb,
                            void* ctx) -> int;

void QsNative_AiChat_Cancel(int id);
auto QsNative_AiChat_LastMetrics() -> char*;
auto QsNative_AiModels_Catalog(const char* providerConfigJSON, const char* providerOrderJSON,
                               const char* configuredModelsJSON) -> char*;
auto QsNative_AiHistory_Restore(const char* modelID, const char* providerID,
                                const char* systemPrompt) -> char*;
auto QsNative_AiHistory_Create(const char* modelID, const char* providerID,
                               const char* systemPrompt) -> char*;
auto QsNative_AiHistory_Close(const char* conversationID) -> char*;
auto QsNative_AiHistory_Resume(const char* modelID, const char* providerID,
                               const char* systemPrompt, const char* currentConversationID,
                               const char* targetConversationID) -> char*;
auto QsNative_AiHistory_ListResume(const char* modelID, const char* providerID,
                                   const char* currentConversationID, const char* query, int limit)
    -> char*;
auto QsNative_AiHistory_UpsertMessage(const char* messageJSON) -> char*;
auto QsNative_AiHistory_MarkMessageDeleted(const char* messageID) -> char*;
auto QsNative_AiHistory_DeleteFromOrdinal(const char* conversationID, int ordinal) -> char*;
auto QsNative_AiHistory_UpsertToolCall(const char* toolCallJSON) -> char*;
auto QsNative_AiHistory_UpsertResponseItems(const char* conversationID, const char* turnID,
                                            int turnOrdinal, const char* responseItemsJSON)
    -> char*;

/* ---------- UI logic helpers ---------- */

auto QsNative_BarModuleLogic_BluetoothDevices(const char* devicesJSON) -> char*;
auto QsNative_BarModuleLogic_ParseLibrepodsTooltip(const char* text) -> char*;
auto QsNative_BarModuleLogic_ActiveMprisPlayer(const char* playersJSON) -> char*;
auto QsNative_BarModuleLogic_SpotifyTrackRef(const char* playerJSON) -> char*;
auto QsNative_BarModuleLogic_LyricsLookupKey(const char* track, const char* artist,
                                             const char* album, const char* lengthMicros) -> char*;
auto QsNative_BarModuleLogic_IsNoLyricsError(const char* errorText) -> char*;
auto QsNative_BarModuleLogic_LyricsSourceInfo(const char* source) -> char*;
auto QsNative_BarModuleLogic_ParseSystemdIdleInhibitors(const char* output) -> char*;
auto QsNative_BarModuleLogic_ParsePortalSessionCount(const char* output) -> char*;
auto QsNative_BarModuleLogic_ParseChargeControlConfig(const char* output) -> char*;
auto QsNative_BarModuleLogic_ChargeControlCommand(const char* mode) -> char*;

/* ---------- Memory ---------- */

/* Free a string returned by any QsNative_* function. */
void QsNative_Free(char* s);

#ifdef __cplusplus
} // extern "C"
#endif
