# OWA Internal API Notes

Captured target account:

- Account: `navon.mitmpl2024@learner.manipal.edu`
- Tenant id: `29bebd42-f1ff-4c3d-9688-067e3460dc1f`
- Redirected Outlook host: `https://outlook.cloud.microsoft`
- App id seen in headers: `9199bf20-a13f-4107-85dc-02114787ef48` (`One Outlook Web`)

## Auth Model

The M365 work/school account path uses a bearer token rather than the consumer `MSAuth1.0 usertoken` header seen on `outlook.live.com`.

Important request headers observed:

- `authorization: Bearer <JWT>`
- `x-anchormailbox: PUID:<puid>@<tenant-id>`
- `x-owa-sessionid: <uuid>`
- `x-owa-canary: <canary>` for search and some OWS endpoints
- `x-client-version: 20260501001.10`
- `x-clientid: <browser client id>`
- `owaappid: 9199bf20-a13f-4107-85dc-02114787ef48`
- `prefer: IdType="ImmutableId", exchange.behavior="IncludeThirdPartyOnlineMeetingProviders"`

The bearer token captured from the page had:

- `aud`: `https://outlook.office.com`
- `scp`: includes `Mail.ReadWrite`, `Mail.Send`, `OWA.AccessAsUser.All`, `SubstrateSearch-Internal.ReadWrite`, and other Outlook/Graph-adjacent scopes.
- `upn`: `navon.mitmpl2024@learner.manipal.edu`

Treat this as browser session auth, not a stable OAuth app credential.

## Core Service Endpoint

Most mailbox list/read operations are Exchange JSON RPC calls:

```text
POST https://outlook.cloud.microsoft/owa/service.svc?action=<Action>&app=Mail&n=<counter>
content-type: application/json; charset=utf-8
action: <Action>
```

The body shape is always:

```json
{
  "__type": "<Action>JsonRequest:#Exchange",
  "Header": {
    "__type": "JsonRequestHeaders:#Exchange",
    "RequestServerVersion": "V2018_01_08",
    "TimeZoneContext": {
      "__type": "TimeZoneContext:#Exchange",
      "TimeZoneDefinition": {
        "__type": "TimeZoneDefinitionType:#Exchange",
        "Id": "India Standard Time"
      }
    }
  },
  "Body": {}
}
```

Some read calls used `RequestServerVersion: V2017_08_18`.

## Captured Actions

### `FindConversation`

Used for the conversation list in the inbox.

Response fields that matter:

- `Body.Conversations[]`
- `ConversationId.Id`
- `ConversationTopic`
- `UniqueSenders`
- `LastDeliveryTime`
- `HasAttachments`
- `MessageCount`
- `UnreadCount`
- `GlobalUnreadCount`
- `ItemIds[]`
- `Preview`
- `LastSender.Mailbox`
- `TotalConversationsInView`
- `IndexedOffset`
- `FolderId`
- `SearchFolderId`

The captured inbox response reported `TotalConversationsInView: 645` and included per-conversation unread counts.

### `FindFolder`

Used to enumerate folders and unread counts.

Important payload choices:

- `FolderShape.BaseShape: IdOnly`
- `AdditionalProperties`: `TotalCount`, `UnreadCount`
- `Traversal: Deep`

This is the best source for unread count by folder.

### `GetFolder`

Used when Outlook needs details for one folder. It can also expose counts for a known folder id.

### `GetConversationItems`

Used to open/read a conversation.

Important response fields:

- `Conversation.ConversationNodes[].Items[]`
- message `ItemId.Id`
- `Subject`
- `From`
- `ToRecipients`
- `DateTimeReceived`
- `Body`
- `Preview`
- `Attachments`

The request can cap body size with `MaximumBodySize`.

## Search Endpoint

Search uses a separate Substrate/Griffin endpoint:

```text
POST https://outlook.cloud.microsoft/searchservice/api/v2/query
```

Captured body for:

```text
from:computer@manipal.edu hasattachments:yes
```

```json
{
  "Scenario": {"Name": "owa.react"},
  "TimeZone": "India Standard Time",
  "EntityRequests": [{
    "EntityType": "Conversation",
    "ContentSources": ["Exchange"],
    "Filter": {
      "Or": [
        {"Term": {"DistinguishedFolderName": "msgfolderroot"}},
        {"Term": {"DistinguishedFolderName": "DeletedItems"}}
      ]
    },
    "From": 0,
    "Query": {"QueryString": "from:computer@manipal.edu hasattachments:yes"},
    "Size": 25,
    "Sort": [
      {"Field": "Score", "SortDirection": "Desc", "Count": 7},
      {"Field": "Time", "SortDirection": "Desc"}
    ],
    "EnableTopResults": true,
    "TopResultsCount": 7
  }]
}
```

Search requires the browser bearer token and `x-owa-canary`.

