// Package main is the CGO c-shared entry point. All //export functions define the C ABI.
package main

/*
#include <stdlib.h>

typedef void (*QsGo_TokenFn)   (void* ctx, const char* token, int done);
typedef void (*QsGo_BrightFn)  (void* ctx, int percent, const char* device);

// Static wrappers are required to call C function pointers from Go.
static void invoke_token_fn(QsGo_TokenFn fn, void* ctx, const char* token, int done) {
    fn(ctx, token, done);
}
static void invoke_bright_fn(QsGo_BrightFn fn, void* ctx, int percent, const char* device) {
    fn(ctx, percent, device);
}
*/
import "C"
import (
	"unsafe"

	"qs-go/internal/ai"
	"qs-go/internal/backlight"
	"qs-go/internal/ical"
	"qs-go/internal/pacman"
	"qs-go/internal/sysinfo"
	"qs-go/internal/todoist"
)

// ----- SysInfo -----

//export QsGo_SysInfo_Refresh
func QsGo_SysInfo_Refresh(diskDevice *C.char) *C.char {
	dev := C.GoString(diskDevice)
	result := sysinfo.Refresh(dev)
	return C.CString(result)
}

// ----- Backlight -----

//export QsGo_Backlight_Get
func QsGo_Backlight_Get() *C.char {
	return C.CString(backlight.Get())
}

//export QsGo_Backlight_Set
func QsGo_Backlight_Set(percent C.int) *C.char {
	return C.CString(backlight.Set(int(percent)))
}

//export QsGo_Backlight_Monitor
func QsGo_Backlight_Monitor(cb C.QsGo_BrightFn, ctx unsafe.Pointer) C.int {
	id := backlight.Monitor(func(percent int, device string) {
		cDevice := C.CString(device)
		C.invoke_bright_fn(cb, ctx, C.int(percent), cDevice)
		C.free(unsafe.Pointer(cDevice))
	})
	return C.int(id)
}

//export QsGo_Backlight_StopMonitor
func QsGo_Backlight_StopMonitor(id C.int) {
	backlight.StopMonitor(int(id))
}

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
func QsGo_Ical_Refresh(envFile *C.char, days C.int) *C.char {
	return C.CString(ical.Refresh(C.GoString(envFile), int(days)))
}

// ----- AI models -----

//export QsGo_AiModels_Refresh
func QsGo_AiModels_Refresh(openaiKey, geminiKey, baseURL *C.char) *C.char {
	return C.CString(ai.RefreshModels(C.GoString(openaiKey), C.GoString(geminiKey), C.GoString(baseURL)))
}

// ----- AI chat -----

//export QsGo_AiChat_Stream
func QsGo_AiChat_Stream(
	modelID, openaiKey, geminiKey, baseURL, systemPrompt,
	historyJSON, message, attachmentsJSON *C.char,
	cb C.QsGo_TokenFn, ctx unsafe.Pointer,
) C.int {
	id := ai.Stream(
		C.GoString(modelID),
		C.GoString(openaiKey),
		C.GoString(geminiKey),
		C.GoString(baseURL),
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

// ----- Todoist -----

//export QsGo_Todoist_List
func QsGo_Todoist_List(envFile *C.char) *C.char {
	return C.CString(todoist.ListTasks(C.GoString(envFile)))
}

//export QsGo_Todoist_Action
func QsGo_Todoist_Action(envFile, verb, argsJSON *C.char) *C.char {
	return C.CString(todoist.Action(C.GoString(envFile), C.GoString(verb), C.GoString(argsJSON)))
}

// ----- Memory management -----

//export QsGo_Free
func QsGo_Free(s *C.char) {
	C.free(unsafe.Pointer(s))
}

func main() {}
