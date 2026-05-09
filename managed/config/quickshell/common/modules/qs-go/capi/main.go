// Package main is the CGO c-shared entry point. All //export functions define the C ABI.
package main

/*
#include <stdlib.h>

typedef void (*QsGo_TokenFn)   (void* ctx, const char* token, int done);

// Static wrappers are required to call C function pointers from Go.
static void invoke_token_fn(QsGo_TokenFn fn, void* ctx, const char* token, int done) {
    fn(ctx, token, done);
}
*/
import "C"
import (
	"unsafe"

	"qs-go/internal/ai"
	"qs-go/internal/appconfig"
	"qs-go/internal/chatstore"
	"qs-go/internal/ical"
	"qs-go/internal/pacman"
	"qs-go/internal/secrets"
	"qs-go/internal/todoist"
)

// ----- Pacman -----

//export QsGo_Pacman_Refresh
func QsGo_Pacman_Refresh(noAur C.int) *C.char {
	return C.CString(pacman.Refresh(noAur != 0))
}

//export QsGo_Pacman_Sync
func QsGo_Pacman_Sync() *C.char {
	return C.CString(pacman.Sync())
}

// ----- iCal -----

//export QsGo_Ical_Refresh
func QsGo_Ical_Refresh(days C.int) *C.char {
	return C.CString(ical.Refresh(int(days)))
}

// ----- Config / secrets resolver -----

//export QsGo_Config_Resolve
func QsGo_Config_Resolve() *C.char {
	return C.CString(appconfig.ResolveJSON(secrets.NewResolver()))
}

//export QsGo_AiMcp_Refresh
func QsGo_AiMcp_Refresh(configJSON *C.char) *C.char {
	return C.CString(ai.RefreshMcp(C.GoString(configJSON)))
}

//export QsGo_AiMcp_GetPrompt
func QsGo_AiMcp_GetPrompt(configJSON, serverID, promptName, argsJSON *C.char) *C.char {
	return C.CString(ai.GetMcpPrompt(
		C.GoString(configJSON),
		C.GoString(serverID),
		C.GoString(promptName),
		C.GoString(argsJSON),
	))
}

//export QsGo_AiMcp_ReadResource
func QsGo_AiMcp_ReadResource(configJSON, serverID, uri *C.char) *C.char {
	return C.CString(ai.ReadMcpResource(
		C.GoString(configJSON),
		C.GoString(serverID),
		C.GoString(uri),
	))
}

// ----- AI chat -----

//export QsGo_AiChat_Stream
func QsGo_AiChat_Stream(
	modelID, providerConfigJSON, mcpConfigJSON, systemPrompt,
	historyJSON, message, attachmentsJSON *C.char,
	cb C.QsGo_TokenFn, ctx unsafe.Pointer,
) C.int {
	id := ai.Stream(
		C.GoString(modelID),
		C.GoString(providerConfigJSON),
		C.GoString(mcpConfigJSON),
		C.GoString(systemPrompt),
		C.GoString(historyJSON),
		C.GoString(message),
		C.GoString(attachmentsJSON),
		func(token string, done int) {
			cToken := C.CString(token)
			C.invoke_token_fn(cb, ctx, cToken, C.int(done))
			C.free(unsafe.Pointer(cToken))
		},
	)
	return C.int(id)
}

//export QsGo_AiChat_Cancel
func QsGo_AiChat_Cancel(id C.int) {
	ai.Cancel(int32(id))
}

//export QsGo_AiChat_LastMetrics
func QsGo_AiChat_LastMetrics() *C.char {
	return C.CString(ai.LastMetricsJSON())
}

//export QsGo_AiHistory_Apply
func QsGo_AiHistory_Apply(actionJSON *C.char) *C.char {
	return C.CString(chatstore.ApplyJSON(C.GoString(actionJSON)))
}

// ----- Todoist -----

//export QsGo_Todoist_List
func QsGo_Todoist_List(cachePath *C.char, preferCache C.int) *C.char {
	return C.CString(todoist.ListTasks(C.GoString(cachePath), preferCache != 0))
}

//export QsGo_Todoist_Action
func QsGo_Todoist_Action(verb, argsJSON *C.char) *C.char {
	return C.CString(todoist.Action(C.GoString(verb), C.GoString(argsJSON)))
}

// ----- Memory management -----

//export QsGo_Free
func QsGo_Free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
