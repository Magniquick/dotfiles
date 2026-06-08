# Search

Outlook Web accepts a familiar query string directly in `/searchservice/api/v2/query`.

Observed examples:

```text
from:computer@manipal.edu hasattachments:yes
isread:no
subject:"Exam Location"
from:slcm.admin@manipal.edu
```

The search endpoint should be treated as Outlook's own parser. The client does not translate the query into IMAP or Graph filters.

## Returned Counts

Search responses can include totals in provider-specific response blocks, but this is less stable than the folder/conversation APIs. The CLI reports:

- `returned_count`: number of rows parsed from this page.
- `estimated_total`: best-effort total when present.
- `from`: requested offset.
- `limit`: requested page size.

Do not confuse `returned_count` with total matches.

## Result Shape

The parser accepts several shapes because the backend response changes over time:

- `EntitySets[].Results[]`
- `EntitySets[].ResultSets[].Results[]`
- `EntitySets[].Items[]`

For each result, the client preserves the raw object and tries to normalize:

- id
- subject/topic
- sender
- received time
- preview
- unread state
- attachment state

