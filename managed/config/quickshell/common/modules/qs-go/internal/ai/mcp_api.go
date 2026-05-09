package ai

import aimcp "qs-go/internal/ai/mcp"

// RefreshMcp refreshes MCP server state and returns a JSON snapshot.
func RefreshMcp(configJSON string) string {
	return aimcp.Refresh(configJSON)
}

// GetMcpPrompt reads a prompt from an MCP server.
func GetMcpPrompt(configJSON, serverID, promptName, argsJSON string) string {
	return aimcp.GetPrompt(configJSON, serverID, promptName, argsJSON)
}

// ReadMcpResource reads a resource from an MCP server.
func ReadMcpResource(configJSON, serverID, uri string) string {
	return aimcp.ReadResource(configJSON, serverID, uri)
}
