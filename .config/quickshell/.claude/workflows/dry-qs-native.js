export const meta = {
  name: 'dry-qs-native',
  description: 'DRY out the qs-native Rust codebase. GPT-5.5 (Codex) fans out across file groups to scan and verify; Opus judges each batch; Sonnet applies fixes. Also moves logic from QML/QS into Rust where appropriate.',
  phases: [
    { title: 'Scan', detail: 'GPT-5.5 (Codex) fans out across file groups to find candidates' },
    { title: 'Judge', detail: 'Opus dedups and decides what genuinely simplifies the code', model: 'opus' },
    { title: 'Fix', detail: 'Sonnet applies each approved change in parallel' },
    { title: 'Verify', detail: 'GPT-5.5 (Codex) runs clippy and self-heals errors' },
  ],
}

const ROOT = '/home/magni/.local/share/dotbak/managed/config/quickshell'
const SRC  = `${ROOT}/common/modules/qs-native/qsnative-rust/src`
const BAR  = `${ROOT}/bar`
const LP   = `${ROOT}/leftpanel`

// Balanced file groups (~1.5k lines each) so no single scan agent reads the whole tree.
// Keep every *.rs in exactly one group — a stale list silently drops files from coverage.
const GROUPS = [
  { id: 'chatstore',   files: ['chatstore.rs'] },
  { id: 'mcp',         files: ['mcp.rs', 'email.rs', 'lib.rs', 'utils.rs'] },
  { id: 'ai',          files: ['ai.rs', 'ai/rig_agent.rs'] },
  { id: 'sysinfo',     files: ['sys_info.rs', 'secrets.rs', 'bin/qs-secrets.rs'] },
  { id: 'backlight',   files: ['backlight.rs', 'todoist.rs'] },
  { id: 'netstats',    files: ['net_stats.rs', 'bar_module_logic.rs'] },
  { id: 'privacy',     files: ['privacy.rs', 'ical.rs', 'app_config.rs'] },
  { id: 'auth',        files: ['google_auth.rs', 'bin/qs-google-auth.rs', 'gmail.rs', 'config_resolver.rs'] },
  { id: 'services',    files: ['bluetooth.rs', 'idle.rs', 'systemd_failed.rs', 'pacman.rs', 'keyboard_lock.rs'] },
]

const ALL_FILES = GROUPS.flatMap(g => g.files)

const FIND_SCHEMA = {
  type: 'object',
  properties: {
    opportunities: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id:          { type: 'string' },
          kind:        { type: 'string', enum: [
            'duplicate_code', 'stdlib_replacement', 'crate_replacement',
            'dead_code', 'merge_helpers', 'qml_to_rust',
          ]},
          description: { type: 'string' },
          files:       { type: 'array', items: { type: 'string' } },
          lines:       { type: 'string' },
        },
        required: ['id', 'kind', 'description', 'files'],
      },
    },
    done: { type: 'boolean' },
  },
  required: ['opportunities', 'done'],
}

const JUDGE_SCHEMA = {
  type: 'object',
  properties: {
    approved: {
      type: 'array',
      items: { type: 'string', description: 'opportunity id to proceed with' },
    },
    reasoning: { type: 'string' },
  },
  required: ['approved'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    applied:     { type: 'boolean' },
    skip_reason: { type: 'string' },
    summary:     { type: 'string' },
  },
  required: ['applied'],
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    passed:  { type: 'boolean', description: 'true only if clippy exits clean after fixes' },
    summary: { type: 'string' },
  },
  required: ['passed'],
}

// Scan/Verify run via codex:codex-rescue, which reaches Context7 through Codex's own MCP config.
const C7_CODEX = `Confirm any stdlib/crate API exists before relying on it. You are a Codex session
with Context7 MCP available — call the Codex-native tools directly (NOT ToolSearch, NOT WebFetch):
  1. mcp__context7.resolve_library_id { libraryName }  -> a Context7 library id
  2. mcp__context7.query_docs { context7CompatibleLibraryID, topic, tokens }`

// The Fix phase runs as a default workflow agent, which has NO Context7. Use docs.rs via WebFetch.
const DOCS_FIX = `Confirm any stdlib/crate API exists before applying a replacement. Context7 is NOT
available to you here; use WebFetch against docs.rs instead, e.g.
WebFetch https://docs.rs/<crate>/latest/<crate>/ to verify the symbol and signature.`

const SCAN_LOOKFOR = `Look for:
1. Duplicated logic across files (error helpers, config loading, runtime creation, etc.)
2. Hand-rolled code that stdlib or an already-imported crate provides
3. Dead functions or structs
4. Small helpers repeated in multiple files that belong in a shared place
5. Verbose iterator chains replaceable by a single combinator
6. QML doing non-trivial data parsing, transformation, or business logic that belongs in Rust
   (the Qt/Rust boundary should push logic Rust-ward; QML should only bind and display)

Rules:
- Be concrete: exact file paths and line ranges.
- Only suggest changes that require no new crate dependencies unless it is already in Cargo.toml.
- Use a stable lowercase-hyphen ID for each finding (prefix it so it is unique across files).
- If you spot a helper that looks duplicated in a file you were NOT assigned, still flag it as
  duplicate_code and name the other file — the judge will dedup across groups.`

// Per-agent retry: agent() resolves to null on a terminal failure (e.g. a stream idle timeout
// from a flaky network mid/late in the response). A valid-but-empty result is a truthy object,
// so this only retries genuine failures — it never re-runs a successful agent, and it retries
// the single failed agent rather than restarting the whole phase.
async function tryAgent(prompt, opts, attempts = 4) {
  for (let i = 1; i <= attempts; i++) {
    const r = await agent(prompt, opts)
    if (r) return r
    if (i < attempts) log(`  retry ${opts.label || 'agent'} (attempt ${i + 1}/${attempts}) — previous call failed`)
  }
  log(`  gave up on ${opts.label || 'agent'} after ${attempts} attempts`)
  return null
}

let totalFixes = 0
let iteration = 0
let consecutiveEmpty = 0
let verifyFailed = false
const MAX_ITERATIONS = 8
const seenIds = new Set()

while (
  consecutiveEmpty < 2 &&
  iteration < MAX_ITERATIONS &&
  (!budget.total || budget.remaining() > 60_000)
) {
  iteration++
  log(`=== Iteration ${iteration} ===`)
  phase('Scan')

  // Fan out: each Codex agent reads only its small group of files.
  const groupScans = await parallel(
    GROUPS.map(g => () => tryAgent(
      `Audit these qs-native Rust files for simplification opportunities.

Read ONLY these files (full paths):
${g.files.map(f => `  ${SRC}/${f}`).join('\n')}

For cross-file context, the full module list is: ${ALL_FILES.join(', ')}

${SCAN_LOOKFOR}

${C7_CODEX}

Skip these already-handled finding IDs: ${JSON.stringify([...seenIds])}
If you find nothing new, return an empty opportunities array with done: true.`,
      { label: `scan:${g.id}`, phase: 'Scan', schema: FIND_SCHEMA, agentType: 'codex:codex-rescue' }
    ))
  )

  // One extra agent for the QML→Rust boundary.
  const qmlScan = await tryAgent(
    `Audit selected QML for logic that should move into the qs-native Rust plugin.

Read ${BAR}/services/CalendarService.qml, ${LP}/LeftPanel.qml, and any QML under ${BAR}
that does non-trivial data parsing, transformation, or business logic (not just binding/display).

Flag cases where QML reimplements parsing/transformation that the Rust side could expose as
richer typed properties. ${SCAN_LOOKFOR}

Skip these already-handled finding IDs: ${JSON.stringify([...seenIds])}
If you find nothing new, return an empty opportunities array with done: true.`,
    { label: 'scan:qml', phase: 'Scan', schema: FIND_SCHEMA, agentType: 'codex:codex-rescue' }
  )

  const all = [...groupScans, qmlScan]
    .filter(Boolean)
    .flatMap(s => s.opportunities || [])

  const fresh = all.filter(o => !seenIds.has(o.id))
  fresh.forEach(o => seenIds.add(o.id))

  if (fresh.length === 0) {
    consecutiveEmpty++
    log(`No new candidates (${consecutiveEmpty}/2)`)
    if (consecutiveEmpty >= 2) break
    continue
  }

  consecutiveEmpty = 0
  log(`${fresh.length} candidates across ${[...new Set(fresh.flatMap(o => o.files))].length} files — sending to Opus`)

  phase('Judge')

  const judgment = await tryAgent(
    `You are reviewing proposed code simplifications for a Quickshell Rust/QML codebase.
Approve only changes that genuinely make the code simpler, clearer, or better structured.
Reject anything cosmetic, risky, or a lateral trade rather than a net improvement.
The candidates come from independent per-file scanners, so DEDUP overlapping findings:
if two ids describe the same duplication, approve only one (the better-scoped one).

Criteria for approval:
- Removes real duplication (not just superficial similarity)
- Replaces custom code with a stdlib/crate equivalent that is demonstrably cleaner
- Moves logic from QML to Rust in a way that makes the boundary cleaner
- Eliminates dead code

Do NOT approve if:
- The change is purely stylistic with no structural gain
- The "replacement" API is equivalent in verbosity
- The QML→Rust move would require significant new Rust surface area for marginal gain
- The change might alter behaviour in edge cases

Before approving, spot-read the cited files (you have read tools) to confirm each claim is real —
never approve on the description alone.

Candidates:
${JSON.stringify(fresh, null, 2)}`,
    { schema: JUDGE_SCHEMA, phase: 'Judge', model: 'opus' }
  )

  const approved = fresh.filter(o => judgment?.approved?.includes(o.id))
  log(`Opus approved ${approved.length}/${fresh.length}: ${judgment?.reasoning?.slice(0, 160) || ''}`)

  if (approved.length === 0) {
    consecutiveEmpty++
    log(`Nothing approved (${consecutiveEmpty}/2)`)
    if (consecutiveEmpty >= 2) break
    continue
  }

  phase('Fix')

  // Direct parallel edits to the working tree. Opus dedups so approved fixes target distinct
  // files; verify (clippy) catches any residual breakage.
  const results = await parallel(
    approved.map(opp => () => tryAgent(
      `Apply this change to the qs-native codebase:

ID: ${opp.id}
Kind: ${opp.kind}
Files: ${opp.files.join(', ')}
Lines: ${opp.lines || 'see description'}
What to do: ${opp.description}

Steps:
1. Read the relevant files.
2. If you need to confirm a stdlib/crate API:
${DOCS_FIX}
3. Apply the minimal change. Do not expand scope.
4. Behaviour must be identical after the change.
5. If after reading the code you judge the change risky or already done, skip and say why.

Root: ${ROOT}`,
      { label: `fix:${opp.id}`, phase: 'Fix', schema: FIX_SCHEMA, model: 'sonnet' }
    ).then(fix => ({ opp, fix })))
  )

  const applied = results.filter(Boolean).filter(r => r.fix?.applied)
  totalFixes += applied.length
  log(`Applied ${applied.length}/${approved.length}`)
  applied.forEach(r => log(`  ✓ ${r.opp.id}: ${r.fix?.summary || ''}`))

  if (applied.length === 0) {
    consecutiveEmpty++
    continue
  }

  phase('Verify')

  const verify = await tryAgent(
    `Run clippy on the qs-native workspace and fix any errors it reports.

cd ${ROOT}
cargo clippy --manifest-path common/modules/Cargo.toml -p qsnative_rust --release --all-targets -- -D warnings

Fix any errors introduced by recent changes. Keep fixes minimal.
Set passed true only if clippy exits clean after your fixes.`,
    { phase: 'Verify', agentType: 'codex:codex-rescue', schema: VERIFY_SCHEMA }
  )

  if (verify && verify.passed === false) {
    log(`!!! Verify FAILED: ${verify.summary || 'clippy still failing'} — stopping loop`)
    verifyFailed = true
    break
  }
  log(`Verify ${verify?.passed ? 'passed' : 'inconclusive'}: ${verify?.summary || ''}`)
}

const stopReason = verifyFailed ? 'verify-failed'
  : iteration >= MAX_ITERATIONS ? 'max-iterations'
  : (budget.total && budget.remaining() <= 60_000) ? 'budget'
  : 'converged'
log(`Done (${stopReason}). ${totalFixes} fixes over ${iteration} iterations.`)
return { totalFixes, iterations: iteration, stopReason, verifyFailed, seen: [...seenIds] }
