export const meta = {
  name: 'dry-qs-native',
  description: 'DRY out the qs-native Rust codebase. Opus judges each batch; Sonnet scans and fixes. Also moves logic from QML/QS into Rust where appropriate.',
  phases: [
    { title: 'Scan', detail: 'Sonnet reads all source and finds candidates' },
    { title: 'Judge', detail: 'Opus decides what genuinely simplifies the code', model: 'opus' },
    { title: 'Fix', detail: 'Sonnet applies each approved change in parallel' },
    { title: 'Verify', detail: 'Sonnet runs clippy and self-heals errors' },
  ],
}

const ROOT = '/home/magni/.local/share/dotbak/managed/config/quickshell'
const SRC  = `${ROOT}/common/modules/qs-native/qsnative-rust/src`
const BAR  = `${ROOT}/bar`
const LP   = `${ROOT}/leftpanel`

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

const C7 = `Context7 MCP is available for Rust API lookups:
  1. mcp__plugin_context7_context7__resolve-library-id { libraryName, query }
  2. mcp__plugin_context7_context7__query-docs { context7CompatibleLibraryID, tokens, topic }
Use it to confirm a stdlib/crate API exists before suggesting it as a replacement.`

let consecutiveEmpty = 0
let totalFixes = 0
let iteration = 0
let seenIds = new Set()

while (consecutiveEmpty < 2) {
  iteration++
  log(`=== Iteration ${iteration} ===`)
  phase('Scan')

  const scan = await agent(
    `Audit the qs-native Rust plugin and its QML callers for simplification opportunities.

Rust source: ${SRC}
Also read selected QML — check ${BAR}/services/CalendarService.qml, ${LP}/LeftPanel.qml,
and any QML file that does non-trivial data transformation or logic that could move to Rust.

Read ALL Rust files: lib.rs, app_config.rs, secrets.rs, google_auth.rs, ical.rs, gmail.rs,
mcp.rs, ai.rs, ai/rig_agent.rs, bar_module_logic.rs, config_resolver.rs,
chatstore.rs, privacy.rs, pacman.rs, net_stats.rs, sys_info.rs, todoist.rs

Look for:
1. Duplicated logic across files (error helpers, config loading, runtime creation, etc.)
2. Hand-rolled code that stdlib or an already-imported crate provides
3. Dead functions or structs
4. Small helpers repeated in multiple files that belong in a shared place
5. Verbose iterator chains replaceable by a single combinator
6. QML doing non-trivial data parsing, transformation, or business logic that belongs in Rust
   (the Qt/Rust boundary should push logic Rust-ward; QML should only bind and display)

${C7}

Rules:
- Be concrete: exact file paths and line ranges.
- Only suggest changes that require no new crate dependencies unless it is already in Cargo.toml.
- Use a stable lowercase-hyphen ID for each finding.
- Skip already-seen IDs: ${JSON.stringify([...seenIds])}
- If nothing new, set done: true.`,
    { schema: FIND_SCHEMA, phase: 'Scan', model: 'sonnet' }
  )

  if (!scan || scan.done || scan.opportunities.length === 0) {
    consecutiveEmpty++
    log(`Empty scan (${consecutiveEmpty}/2)`)
    if (consecutiveEmpty >= 2) break
    continue
  }

  const fresh = scan.opportunities.filter(o => !seenIds.has(o.id))
  fresh.forEach(o => seenIds.add(o.id))

  if (fresh.length === 0) {
    consecutiveEmpty++
    log(`All findings already seen (${consecutiveEmpty}/2)`)
    if (consecutiveEmpty >= 2) break
    continue
  }

  consecutiveEmpty = 0
  log(`${fresh.length} candidates — sending to Opus`)

  phase('Judge')

  const judgment = await agent(
    `You are reviewing a list of proposed code simplifications for a Quickshell Rust/QML codebase.
Your job: approve only changes that genuinely make the code simpler, clearer, or better structured.
Reject anything that is cosmetic, risky, or a lateral trade rather than a net improvement.

Criteria for approval:
- Removes real duplication (not just superficial similarity)
- Replaces custom code with a stdlib/crate equivalent that is demonstrably cleaner
- Moves logic from QML to Rust in a way that makes the boundary cleaner (less parsing in QML, richer types on the Rust side)
- Eliminates dead code

Do NOT approve if:
- The change is purely stylistic with no structural gain
- The "replacement" API is equivalent in verbosity
- The QML→Rust move would require significant new Rust surface area for marginal gain
- The change might alter behaviour in edge cases

Candidates:
${JSON.stringify(fresh, null, 2)}`,
    { schema: JUDGE_SCHEMA, phase: 'Judge', model: 'opus' }
  )

  const approved = fresh.filter(o => judgment?.approved?.includes(o.id))
  log(`Opus approved ${approved.length}/${fresh.length}: ${judgment?.reasoning?.slice(0, 120) || ''}`)

  if (approved.length === 0) {
    consecutiveEmpty++
    log(`Nothing approved (${consecutiveEmpty}/2)`)
    if (consecutiveEmpty >= 2) break
    continue
  }

  phase('Fix')

  const results = await pipeline(
    approved,
    (opp) => agent(
      `Apply this change to the qs-native codebase:

ID: ${opp.id}
Kind: ${opp.kind}
Files: ${opp.files.join(', ')}
Lines: ${opp.lines || 'see description'}
What to do: ${opp.description}

Steps:
1. Read the relevant files.
2. Use Context7 if you need to confirm a stdlib/crate API:
${C7}
3. Apply the minimal change. Do not expand scope.
4. Behaviour must be identical after the change.
5. If after reading the code you judge the change risky or already done, skip and say why.

Root: ${ROOT}`,
      { label: `fix:${opp.id}`, phase: 'Fix', schema: FIX_SCHEMA, model: 'sonnet' }
    ).then(fix => ({ opp, fix }))
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

  await agent(
    `Run clippy on the qs-native workspace and fix any errors it reports.

cd ${ROOT}
cargo clippy --manifest-path common/modules/Cargo.toml -p qsnative_rust --release --all-targets -- -D warnings

Fix any errors introduced by recent changes. Keep fixes minimal. Report pass or fail.`,
    { phase: 'Verify', model: 'sonnet' }
  )
}

log(`Done. ${totalFixes} fixes over ${iteration} iterations.`)
return { totalFixes, iterations: iteration, seen: [...seenIds] }
