# Outlook Internal API

This directory contains a local, browser-session-backed client for the Outlook Web internal APIs used by `navon.mitmpl2024@learner.manipal.edu`.

It targets the currently observed Outlook host:

- UI: `https://outlook.office.com/mail/?login_hint=navon.mitmpl2024%40learner.manipal.edu`
- Redirected app/API host: `https://outlook.cloud.microsoft`
- Main Exchange-shaped RPC endpoint: `POST /owa/service.svc?action=...&app=Mail&n=N`
- Search endpoint: `POST /searchservice/api/v2/query`

No bearer tokens or cookies are committed. Runtime auth snapshots live in `outlook/.secrets/session.json`.

## Quick Start

Install dependencies:

```sh
cd outlook
uv sync
uv run playwright install chromium
```

Extract a fresh auth snapshot from the signed-in Outlook Web session:

```sh
uv run outlook-internal auth refresh
```

Run the useful mailbox operations:

```sh
uv run outlook-internal folders
uv run outlook-internal unread
uv run outlook-internal inbox --limit 25
uv run outlook-internal search 'from:computer@manipal.edu hasattachments:yes' --limit 25
uv run outlook-internal read '<conversation-id-or-item-id>'
```

If a direct API call returns `401`, `403`, or an OWA canary/session error, refresh auth again:

```sh
uv run outlook-internal auth refresh --headed
```

`auth refresh` also records the currently observed root, inbox, and search folder ids so the common commands do not require manual ID arguments. If Outlook changes the boot sequence and those IDs are not captured, pass `--parent-folder-id` or `--folder-id` manually from a capture.

## What Is Implemented

- Browser auth capture through Playwright.
- Direct OWA `service.svc` calls using captured bearer/canary/session/anchor headers.
- Folder listing with `TotalCount` and `UnreadCount`.
- Inbox conversation listing using `FindConversation`.
- Total unread summary derived from folder counts and from conversation rows.
- Outlook Web search using `/searchservice/api/v2/query`.
- Conversation reading through `GetConversationItems`.
- Redacted capture tooling for future endpoint discovery.

## Why This Exists

The target account is an M365/Outlook Web mailbox where the normal Microsoft 365 public surfaces may not expose the desired IMAP-style behavior. Outlook Web itself already has a working mail client, so this project reuses the same internal APIs from the signed-in browser session.

## Files

- `src/outlook_internal/session.py`: auth snapshot extraction and token freshness helpers.
- `src/outlook_internal/client.py`: direct internal API client.
- `src/outlook_internal/cli.py`: command-line workflows.
- `src/outlook_internal/payloads.py`: Exchange JSON payload builders.
- `docs/owa-internal-api.md`: endpoint and payload notes from live capture.
- `docs/token-refresh.md`: how auth refresh works.
- `docs/search.md`: search syntax and response notes.
- `docs/playwright-capture.md`: how to reproduce and extend traffic capture.
