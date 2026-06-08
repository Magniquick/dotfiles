from outlook_internal.client import normalize_conversations, normalize_folders, normalize_search_results


def test_normalize_conversations_reports_counts_and_ids():
  data = {
    "Body": {
      "Conversations": [
        {
          "ConversationId": {"Id": "conv"},
          "ConversationTopic": "Exam Location Notification",
          "UniqueSenders": ["MAHE - DO NOT REPLY"],
          "LastSender": {"Mailbox": {"Name": "MAHE", "EmailAddress": "slcm.admin@manipal.edu"}},
          "LastDeliveryTime": "2026-05-08T18:01:23+05:30",
          "HasAttachments": False,
          "MessageCount": 1,
          "UnreadCount": 1,
          "GlobalUnreadCount": 1,
          "ItemIds": [{"Id": "item"}],
          "Preview": "Dear Student",
        }
      ]
    }
  }

  rows = normalize_conversations(data)

  assert rows == [
    {
      "conversation_id": "conv",
      "topic": "Exam Location Notification",
      "unique_senders": ["MAHE - DO NOT REPLY"],
      "last_sender": "slcm.admin@manipal.edu",
      "last_sender_name": "MAHE",
      "last_delivery_time": "2026-05-08T18:01:23+05:30",
      "has_attachments": False,
      "message_count": 1,
      "unread_count": 1,
      "global_unread_count": 1,
      "importance": None,
      "preview": "Dear Student",
      "item_ids": ["item"],
      "raw": data["Body"]["Conversations"][0],
    }
  ]


def test_normalize_folders_finds_response_message_folders():
  data = {
    "Body": {
      "ResponseMessages": {
        "Items": [
          {
            "RootFolder": {
              "Folders": [
                {
                  "FolderId": {"Id": "inbox"},
                  "DisplayName": "Inbox",
                  "TotalCount": 645,
                  "UnreadCount": 22,
                }
              ]
            }
          }
        ]
      }
    }
  }

  assert normalize_folders(data)[0]["unread_count"] == 22


def test_normalize_search_results_handles_entity_sets():
  data = {
    "EntitySets": [
      {
        "Results": [
          {
            "Id": "result",
            "Source": {
              "ConversationTopic": "Seating Allocation",
              "LastSender": {"Mailbox": {"EmailAddress": "computer@manipal.edu"}},
              "HasAttachments": True,
              "UnreadCount": 1,
            },
          }
        ]
      }
    ]
  }

  row = normalize_search_results(data)[0]

  assert row["id"] == "result"
  assert row["topic"] == "Seating Allocation"
  assert row["last_sender"] == "computer@manipal.edu"
  assert row["has_attachments"] is True
