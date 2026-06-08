# Token Refresh

There is no durable refresh token committed here. The supported refresh path is:

1. Open Outlook Web with Playwright.
2. Let the already signed-in Playwright profile acquire fresh OWA tokens.
3. Capture the next OWA/search request headers.
4. Save only the local runtime snapshot in `.secrets/session.json`.

Run:

```sh
uv run outlook-internal auth refresh
```

Use headed mode if Microsoft needs interaction:

```sh
uv run outlook-internal auth refresh --headed
```

The persistent Playwright profile defaults to:

```text
~/.cache/outlook-internal/playwright-profile
```

The first run may need `--headed` so you can complete Microsoft login/MFA. Later refreshes can usually run headless because the profile is already signed in.

## Snapshot Contents

The snapshot stores:

- `base_url`
- `login_url`
- `account`
- `tenant_id`
- `puid_anchor`
- `authorization`
- `x_owa_canary`
- `x_owa_sessionid`
- `x_client_version`
- `x_clientid`
- `owa_app_id`
- `captured_at`
- decoded JWT expiry metadata when available

The committed `.gitignore` excludes `.secrets/`.

## Expiry Detection

The CLI decodes the JWT payload without verifying the signature and checks `exp`. If a token has less than five minutes left, commands fail with a refresh hint unless `--allow-stale` is provided.

## Failure Modes

- `401` / `403`: token expired, account switched, or canary missing.
- `ErrorInvalidClientSecurityContext`: refresh the browser session.
- Empty/consumer mailbox data: verify that the current page title and URL are for the learner account, not `outlook.live.com`.
- Search works but service calls fail: check `authorization`, `x-anchormailbox`, and `prefer`.
- Service calls work but search fails: check `x-owa-canary`, `owaappid`, and `x-clientid`.

## MSAL Cache Fallback

The Outlook page also keeps MSAL entries in browser `localStorage`.

The important access-token entry is the one whose key contains:

```text
accesstoken|9199bf20-a13f-4107-85dc-02114787ef48|29bebd42-f1ff-4c3d-9688-067e3460dc1f|https://outlook.office.com/...mail.readwrite...owa.accessasuser.all...
```

Its JSON value contains:

```json
{
  "credentialType": "AccessToken",
  "secret": "<bearer-token>",
  "target": "https://outlook.office.com/mail.readwrite ..."
}
```

Related refresh token entries are present under `credentialType: RefreshToken`, but this project deliberately does not implement raw refresh-token exchange yet. The safer local behavior is still to let Outlook Web/MSAL refresh itself inside Playwright, then capture the resulting access token.

Observed local keys that help diagnose the signed-in account:

- `sessionTracking_10032003b5c6fbdc`
- `olk-isauthed`
- `olk-OwaClientId`
- `LokiAuthToken`
