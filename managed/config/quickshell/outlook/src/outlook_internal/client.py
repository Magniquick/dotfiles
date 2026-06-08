from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

import niquests

from . import payloads
from .session import SessionSnapshot, new_request_id


class OutlookInternalError(RuntimeError):
  pass


@dataclass
class OutlookInternalClient:
  snapshot: SessionSnapshot
  timeout: float = 30

  def __post_init__(self) -> None:
    self.session = niquests.Session()
    self.counter = 0

  def close(self) -> None:
    self.session.close()

  def _next_n(self) -> int:
    self.counter += 1
    return self.counter

  def _base_headers(self, action: str | None = None, search: bool = False) -> dict[str, str]:
    headers = {
      "authorization": self.snapshot.authorization,
      "content-type": "application/json; charset=utf-8",
      "prefer": 'IdType="ImmutableId", exchange.behavior="IncludeThirdPartyOnlineMeetingProviders"',
      "x-anchormailbox": self.snapshot.x_anchormailbox,
      "x-owa-hosted-ux": "false",
      "x-owa-sessionid": self.snapshot.x_owa_sessionid,
      "x-req-source": "Mail",
    }
    if action:
      headers["action"] = action
    if self.snapshot.x_client_version:
      headers["x-client-version"] = self.snapshot.x_client_version
    if self.snapshot.tenant_id:
      headers["x-tenantid"] = self.snapshot.tenant_id
    if search:
      headers.update(
        {
          "accept-language": "en-US",
          "content-type": "application/json",
          "client-request-id": new_request_id(),
          "client-session-id": self.snapshot.x_owa_sessionid,
          "owaappid": self.snapshot.owa_app_id,
          "scenariotag": "1stPg_cv",
          "x-ms-appname": "owa-reactmail",
          "x-search-griffin-version": "GWSv2",
          "x-routingparameter-sessionkey": self.snapshot.x_anchormailbox,
        }
      )
      if self.snapshot.x_owa_canary:
        headers["x-owa-canary"] = self.snapshot.x_owa_canary
      if self.snapshot.x_clientid:
        headers["x-clientid"] = self.snapshot.x_clientid
    return headers

  def service(self, action: str, body: dict[str, Any]) -> dict[str, Any]:
    url = f"{self.snapshot.base_url}/owa/service.svc?action={action}&app=Mail&n={self._next_n()}"
    response = self.session.post(
      url,
      headers=self._base_headers(action=action),
      json=body,
      timeout=self.timeout,
    )
    if response.status_code >= 400:
      raise OutlookInternalError(f"{action} failed: HTTP {response.status_code}: {response.text[:500]}")
    data = response.json()
    response_code = _first_response_code(data)
    if response_code and response_code != "NoError":
      raise OutlookInternalError(f"{action} failed: {response_code}: {data}")
    return data

  def search(self, query: str, offset: int = 0, limit: int = 25) -> dict[str, Any]:
    cvid = str(uuid.uuid4())
    logical_id = str(uuid.uuid4())
    body = payloads.search_query(
      payloads.SearchQuery(query=query, offset=offset, limit=limit, cvid=cvid, logical_id=logical_id)
    )
    url = f"{self.snapshot.base_url}/searchservice/api/v2/query?n={self._next_n()}"
    response = self.session.post(
      url,
      headers=self._base_headers(search=True),
      json=body,
      timeout=self.timeout,
    )
    if response.status_code >= 400:
      raise OutlookInternalError(f"search failed: HTTP {response.status_code}: {response.text[:500]}")
    data = response.json()
    rows = normalize_search_results(data)
    return {
      "query": query,
      "offset": offset,
      "limit": limit,
      "returned_count": len(rows),
      "estimated_total": estimate_search_total(data),
      "results": rows,
      "raw": data,
    }

  def folders(self, parent_folder_id: str, max_entries: int = 100) -> list[dict[str, Any]]:
    data = self.service("FindFolder", payloads.find_folder(parent_folder_id, max_entries=max_entries))
    return normalize_folders(data)

  def get_folder(self, folder_id_value: str) -> dict[str, Any]:
    data = self.service("GetFolder", payloads.get_folder(folder_id_value))
    folders = normalize_folders(data)
    return folders[0] if folders else {}

  def conversations(
    self,
    folder_id: str,
    search_folder_id: str | None = None,
    offset: int = 0,
    limit: int = 25,
    view_filter: str = "All",
  ) -> dict[str, Any]:
    data = self.service(
      "FindConversation",
      payloads.find_conversation(
        folder_id_value=folder_id,
        search_folder_id=search_folder_id,
        offset=offset,
        limit=limit,
        view_filter=view_filter,
      ),
    )
    conversations = normalize_conversations(data)
    body = data.get("Body", {})
    return {
      "offset": offset,
      "limit": limit,
      "returned_count": len(conversations),
      "matched_count": body.get("TotalConversationsInView"),
      "indexed_offset": body.get("IndexedOffset"),
      "folder_id": _id_value(body.get("FolderId")),
      "search_folder_id": _id_value(body.get("SearchFolderId")),
      "conversations": conversations,
      "raw": data,
    }

  def read_conversation(self, conversation_id: str, max_items: int = 20) -> dict[str, Any]:
    data = self.service(
      "GetConversationItems",
      payloads.get_conversation_items(conversation_id, max_items=max_items),
    )
    return {
      "conversation_id": conversation_id,
      "messages": normalize_messages(data),
      "raw": data,
    }


def _first_response_code(data: dict[str, Any]) -> str | None:
  body = data.get("Body", {})
  if isinstance(body.get("ResponseCode"), str):
    return body["ResponseCode"]
  items = body.get("ResponseMessages", {}).get("Items", [])
  if items and isinstance(items[0], dict):
    return items[0].get("ResponseCode")
  return None


def _id_value(value: Any) -> str | None:
  if isinstance(value, dict):
    return value.get("Id")
  return None


def normalize_conversations(data: dict[str, Any]) -> list[dict[str, Any]]:
  conversations = data.get("Body", {}).get("Conversations", [])
  rows = []
  for conv in conversations:
    item_ids = [_id_value(v) for v in conv.get("ItemIds", []) if _id_value(v)]
    last_sender = conv.get("LastSender", {}).get("Mailbox", {})
    rows.append(
      {
        "conversation_id": _id_value(conv.get("ConversationId")),
        "topic": conv.get("ConversationTopic"),
        "unique_senders": conv.get("UniqueSenders", []),
        "last_sender": last_sender.get("EmailAddress") or last_sender.get("Name"),
        "last_sender_name": last_sender.get("Name"),
        "last_delivery_time": conv.get("LastDeliveryTime") or conv.get("LastDeliveryOrRenewTime"),
        "has_attachments": conv.get("HasAttachments"),
        "message_count": conv.get("MessageCount"),
        "unread_count": conv.get("UnreadCount"),
        "global_unread_count": conv.get("GlobalUnreadCount"),
        "importance": conv.get("Importance"),
        "preview": conv.get("Preview"),
        "item_ids": item_ids,
        "raw": conv,
      }
    )
  return rows


def normalize_folders(data: dict[str, Any]) -> list[dict[str, Any]]:
  folders: list[dict[str, Any]] = []
  body = data.get("Body", {})
  roots: list[Any] = []
  if "ResponseMessages" in body:
    for msg in body.get("ResponseMessages", {}).get("Items", []):
      root = msg.get("RootFolder") or {}
      roots.extend(root.get("Folders", []))
      roots.extend(root.get("Items", []))
  roots.extend(body.get("Folders", []))
  for folder in roots:
    if not isinstance(folder, dict):
      continue
    folders.append(
      {
        "id": _id_value(folder.get("FolderId")),
        "display_name": folder.get("DisplayName"),
        "folder_class": folder.get("FolderClass"),
        "total_count": folder.get("TotalCount"),
        "unread_count": folder.get("UnreadCount"),
        "distinguished_folder_id": folder.get("DistinguishedFolderId"),
        "raw": folder,
      }
    )
  return folders


def normalize_messages(data: dict[str, Any]) -> list[dict[str, Any]]:
  messages: list[dict[str, Any]] = []

  def visit(value: Any) -> None:
    if isinstance(value, dict):
      if value.get("__type", "").startswith("Message:") or value.get("ItemClass") == "IPM.Note":
        mailbox = value.get("From", {}).get("Mailbox", {})
        body = value.get("Body") or value.get("NormalizedBody") or value.get("TextBody") or {}
        messages.append(
          {
            "item_id": _id_value(value.get("ItemId")),
            "subject": value.get("Subject"),
            "from": mailbox.get("EmailAddress") or mailbox.get("Name"),
            "from_name": mailbox.get("Name"),
            "received": value.get("DateTimeReceived"),
            "sent": value.get("DateTimeSent"),
            "is_read": value.get("IsRead"),
            "has_attachments": value.get("HasAttachments"),
            "preview": value.get("Preview"),
            "body": body.get("Value") if isinstance(body, dict) else body,
            "raw": value,
          }
        )
      for child in value.values():
        visit(child)
    elif isinstance(value, list):
      for child in value:
        visit(child)

  visit(data)
  seen: set[str] = set()
  unique = []
  for msg in messages:
    key = msg.get("item_id") or repr(msg.get("raw"))
    if key in seen:
      continue
    seen.add(key)
    unique.append(msg)
  return unique


def normalize_search_results(data: dict[str, Any]) -> list[dict[str, Any]]:
  raw_results: list[dict[str, Any]] = []

  def collect(value: Any) -> None:
    if isinstance(value, dict):
      if isinstance(value.get("Results"), list):
        raw_results.extend(x for x in value["Results"] if isinstance(x, dict))
      if isinstance(value.get("Items"), list) and any(isinstance(x, dict) for x in value["Items"]):
        raw_results.extend(x for x in value["Items"] if isinstance(x, dict))
      for child in value.values():
        collect(child)
    elif isinstance(value, list):
      for child in value:
        collect(child)

  collect(data.get("EntitySets", data))
  rows = []
  for result in raw_results:
    source = result.get("Source") if isinstance(result.get("Source"), dict) else result
    conversation = source.get("Conversation") if isinstance(source.get("Conversation"), dict) else source
    mailbox = (
      conversation.get("LastSender", {}).get("Mailbox", {})
      if isinstance(conversation.get("LastSender"), dict)
      else {}
    )
    rows.append(
      {
        "id": result.get("Id") or _id_value(conversation.get("ConversationId")),
        "topic": conversation.get("ConversationTopic") or conversation.get("Subject") or result.get("Title"),
        "last_sender": mailbox.get("EmailAddress") or mailbox.get("Name") or result.get("Sender"),
        "received": conversation.get("LastDeliveryTime") or conversation.get("DateTimeReceived"),
        "has_attachments": conversation.get("HasAttachments"),
        "unread_count": conversation.get("UnreadCount"),
        "preview": conversation.get("Preview") or result.get("Summary"),
        "raw": result,
      }
    )
  return rows


def estimate_search_total(data: dict[str, Any]) -> int | None:
  candidates: list[int] = []

  def visit(value: Any) -> None:
    if isinstance(value, dict):
      for key in ("Total", "TotalResultCount", "ResultCount", "Hits"):
        candidate = value.get(key)
        if isinstance(candidate, int):
          candidates.append(candidate)
      for child in value.values():
        visit(child)
    elif isinstance(value, list):
      for child in value:
        visit(child)

  visit(data)
  return max(candidates) if candidates else None

