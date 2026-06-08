from outlook_internal import payloads


def test_find_conversation_payload_uses_exchange_shape():
  body = payloads.find_conversation("inbox-id", search_folder_id="search-id", offset=5, limit=10)

  assert body["__type"] == "FindConversationJsonRequest:#Exchange"
  assert body["Header"]["RequestServerVersion"] == "V2018_01_08"
  assert body["Body"]["ParentFolderId"]["BaseFolderId"]["Id"] == "inbox-id"
  assert body["Body"]["SearchFolderId"]["Id"] == "search-id"
  assert body["Body"]["Paging"]["Offset"] == 5
  assert body["Body"]["Paging"]["MaxEntriesReturned"] == 10


def test_search_payload_preserves_outlook_query_string():
  body = payloads.search_query(
    payloads.SearchQuery(
      query="from:computer@manipal.edu hasattachments:yes",
      offset=2,
      limit=7,
      cvid="cvid",
      logical_id="logical",
    )
  )

  request = body["EntityRequests"][0]
  assert body["Scenario"]["Name"] == "owa.react"
  assert request["EntityType"] == "Conversation"
  assert request["Query"]["QueryString"] == "from:computer@manipal.edu hasattachments:yes"
  assert request["From"] == 2
  assert request["Size"] == 7

