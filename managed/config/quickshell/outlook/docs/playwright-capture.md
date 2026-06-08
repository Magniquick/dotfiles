# Playwright Capture

Use this when Outlook changes the payload or a new feature is needed.

```sh
uv run outlook-internal capture --query 'from:computer@manipal.edu hasattachments:yes' --redacted
```

The capture tool:

- opens the learner Outlook URL,
- waits for the mailbox to load,
- records OWA/search requests,
- optionally performs a search,
- redacts `authorization`, cookies, canaries, and token-like headers by default,
- writes JSONL to `examples/captures/`.

Useful filters:

```text
service.svc
searchservice/api/v2/query
GetConversationItems
FindConversation
FindFolder
GetFolder
```

To capture raw headers for private debugging, pass `--raw`. Do not commit the output.

