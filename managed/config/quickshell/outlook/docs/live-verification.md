# Live Verification Notes

These notes describe what was observed with Playwright against the corrected learner account.

## Correct Account

The target URL:

```text
https://outlook.office.com/mail/?login_hint=navon.mitmpl2024%40learner.manipal.edu
```

redirected to:

```text
https://outlook.cloud.microsoft/mail/
```

The loaded page title was:

```text
Mail - NAVON JOHN LUKOSE - 240905602 - MITMPL - Outlook
```

## Inbox Conversation API

Observed request:

```text
POST https://outlook.cloud.microsoft/owa/service.svc?action=FindConversation&app=Mail&n=0
```

Observed auth/header style:

- `authorization: Bearer <JWT>`
- `x-anchormailbox: PUID:10032003B5C6FBDC@29bebd42-f1ff-4c3d-9688-067e3460dc1f`
- `x-owa-sessionid: <uuid>`
- `prefer: IdType="ImmutableId", exchange.behavior="IncludeThirdPartyOnlineMeetingProviders"`

Observed response facts:

- `TotalConversationsInView: 645`
- Per-row fields included `ConversationTopic`, `UniqueSenders`, `UnreadCount`, `GlobalUnreadCount`, `HasAttachments`, `ItemIds`, and `Preview`.
- Example unread conversation topics included `Exam Location Notification`, `IV and VI Semester Summer Lab Timetable May- June 2026`, and `Seating Allocation - End Sem Exam_09-05-2026`.

Direct replay from the authenticated Playwright page also succeeded with the client payload shape:

- HTTP `200`
- `ResponseCode: NoError`
- `TotalConversationsInView: 645`
- 5 requested rows returned
- returned rows contained unread and attachment metadata

## Search API

A Playwright-driven search for:

```text
from:computer@manipal.edu hasattachments:yes
```

triggered:

```text
POST https://outlook.cloud.microsoft/searchservice/api/v2/query
```

The request used:

- `authorization: Bearer <JWT>`
- `x-owa-canary: <canary>`
- `owaappid: 9199bf20-a13f-4107-85dc-02114787ef48`
- `x-clientid: D6B67AD2A4BD4E73ADC2E30EA1FE79B7`
- `x-search-griffin-version: GWSv2`

The posted body preserved the query string exactly in:

```json
{"Query": {"QueryString": "from:computer@manipal.edu hasattachments:yes"}}
```

Direct replay from the authenticated Playwright page also succeeded:

- HTTP `200`
- top-level keys included `ApiVersion`, `SearchTerms`, `EntitySets`, `RestrictedSearchMode`, and `Instrumentation`
- one `EntitySets` block was returned
- the response contained Exchange conversation results for `computer@manipal.edu`

## Browser Token Cache

The Outlook page had MSAL cache entries in `localStorage`, including an access token scoped for Outlook mail and OWA access. The page also exposed:

- `sessionTracking_10032003b5c6fbdc`, with the learner UPN
- `olk-isauthed`
- `olk-OwaClientId`
- `LokiAuthToken` in `sessionStorage`

These validate that token refresh should be delegated to Outlook Web/MSAL and then captured locally.
