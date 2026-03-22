package ai

import aimcp "qs-go/internal/ai/mcp"

func RefreshMcp(configJSON string) string {
	return aimcp.Refresh(configJSON)
}

func GetMcpPrompt(configJSON, serverID, promptName, argsJSON string) string {
	return aimcp.GetPrompt(configJSON, serverID, promptName, argsJSON)
}

func ReadMcpResource(configJSON, serverID, uri string) string {
	return aimcp.ReadResource(configJSON, serverID, uri)
}
