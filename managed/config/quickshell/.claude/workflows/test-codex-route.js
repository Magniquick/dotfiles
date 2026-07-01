export const meta = {
  name: 'test-codex-route',
  description: 'Does codex:codex-rescue reach its Codex-native Context7 MCP when run inside a workflow?',
  phases: [
    { title: 'C7Codex', detail: 'codex:codex-rescue resolves a crate via its own Context7 MCP' },
  ],
}

const C7_SCHEMA = {
  type: 'object',
  properties: {
    reachedContext7: { type: 'boolean', description: 'true ONLY if a Context7 MCP tool actually returned data' },
    libraryId:       { type: 'string', description: 'the resolved Context7 library id (e.g. /serde-rs/serde)' },
    toolNames:       { type: 'array', items: { type: 'string' }, description: 'exact Context7 tool names called' },
    docSnippet:      { type: 'string', description: 'a short verbatim slice of docs returned, to prove real data' },
    notes:           { type: 'string' },
  },
  required: ['reachedContext7', 'notes'],
}

phase('C7Codex')
const codex = await agent(
  `You are running as a Codex session. Codex has a Context7 MCP server configured in its
config.toml ([mcp_servers.context7], url https://mcp.context7.com/mcp). Use YOUR Codex-native
Context7 MCP tools directly — do NOT look in any workflow/ToolSearch registry, and do not use
WebFetch. The Context7 tools are named "resolve-library-id" and "get-library-docs".

Task:
1. Call resolve-library-id for the Rust crate "serde".
2. Call get-library-docs for the resolved id with topic "Serialize derive", small token budget.
3. Report the resolved libraryId, the exact tool names you called, and a short verbatim
   docSnippet from the returned docs (proof of real data). Set reachedContext7 true only if a
   Context7 tool actually returned content. If Context7 is genuinely unavailable in your session,
   say so plainly and set reachedContext7 false. Do NOT fabricate.`,
  { schema: C7_SCHEMA, phase: 'C7Codex', agentType: 'codex:codex-rescue' }
)
log(`C7Codex: ${JSON.stringify(codex)}`)

return { codexReachedContext7: !!codex?.reachedContext7, codex }
