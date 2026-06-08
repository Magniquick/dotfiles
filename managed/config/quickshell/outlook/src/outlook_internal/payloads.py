from __future__ import annotations

from dataclasses import dataclass
from typing import Any


DEFAULT_TIME_ZONE = "India Standard Time"


def header(version: str = "V2018_01_08", time_zone: str = DEFAULT_TIME_ZONE) -> dict[str, Any]:
  return {
    "__type": "JsonRequestHeaders:#Exchange",
    "RequestServerVersion": version,
    "TimeZoneContext": {
      "__type": "TimeZoneContext:#Exchange",
      "TimeZoneDefinition": {
        "__type": "TimeZoneDefinitionType:#Exchange",
        "Id": time_zone,
      },
    },
  }


def folder_id(folder_id_value: str) -> dict[str, str]:
  return {"__type": "FolderId:#Exchange", "Id": folder_id_value}


def target_folder_id(folder_id_value: str) -> dict[str, Any]:
  return {"__type": "TargetFolderId:#Exchange", "BaseFolderId": folder_id(folder_id_value)}


def find_folder(parent_folder_id: str, max_entries: int = 100) -> dict[str, Any]:
  return {
    "__type": "FindFolderJsonRequest:#Exchange",
    "Header": header(),
    "Body": {
      "__type": "FindFolderRequest:#Exchange",
      "FolderShape": {
        "__type": "FolderResponseShape:#Exchange",
        "BaseShape": "IdOnly",
        "AdditionalProperties": [
          {"__type": "PropertyUri:#Exchange", "FieldURI": "DisplayName"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "FolderClass"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "TotalCount"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "UnreadCount"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "DistinguishedFolderId"},
        ],
      },
      "Paging": {
        "__type": "IndexedPageView:#Exchange",
        "BasePoint": "Beginning",
        "Offset": 0,
        "MaxEntriesReturned": max_entries,
      },
      "ParentFolderIds": [folder_id(parent_folder_id)],
      "ReturnParentFolder": True,
      "Traversal": "Deep",
    },
  }


def get_folder(folder_id_value: str) -> dict[str, Any]:
  return {
    "__type": "GetFolderJsonRequest:#Exchange",
    "Header": header(),
    "Body": {
      "FolderShape": {
        "__type": "FolderResponseShape:#Exchange",
        "BaseShape": "IdOnly",
        "AdditionalProperties": [
          {"__type": "PropertyUri:#Exchange", "FieldURI": "DisplayName"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "TotalCount"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "UnreadCount"},
        ],
      },
      "FolderIds": [folder_id(folder_id_value)],
    },
  }


def find_conversation(
  folder_id_value: str,
  search_folder_id: str | None = None,
  offset: int = 0,
  limit: int = 25,
  view_filter: str = "All",
) -> dict[str, Any]:
  body: dict[str, Any] = {
    "ParentFolderId": target_folder_id(folder_id_value),
    "ConversationShape": {
      "__type": "ConversationResponseShape:#Exchange",
      "BaseShape": "IdOnly",
    },
    "ShapeName": "ReactConversationListView",
    "Paging": {
      "__type": "IndexedPageView:#Exchange",
      "BasePoint": "Beginning",
      "Offset": offset,
      "MaxEntriesReturned": limit,
    },
    "ViewFilter": view_filter,
    "SortOrder": [
      {
        "__type": "SortResults:#Exchange",
        "Order": "Descending",
        "Path": {"__type": "PropertyUri:#Exchange", "FieldURI": "ConversationImportance"},
      },
      {
        "__type": "SortResults:#Exchange",
        "Order": "Descending",
        "Path": {"__type": "PropertyUri:#Exchange", "FieldURI": "ConversationLastDeliveryTime"},
      },
    ],
    "FocusedViewFilter": 0,
  }
  if search_folder_id:
    body["SearchFolderId"] = folder_id(search_folder_id)

  return {
    "__type": "FindConversationJsonRequest:#Exchange",
    "Header": header(),
    "Body": body,
  }


def get_conversation_items(
  conversation_id: str,
  max_items: int = 20,
  max_body_size: int = 2_097_152,
) -> dict[str, Any]:
  return {
    "__type": "GetConversationItemsJsonRequest:#Exchange",
    "Header": header("V2017_08_18"),
    "Body": {
      "__type": "GetConversationItemsRequest:#Exchange",
      "Conversations": [
        {
          "__type": "ConversationRequestType:#Exchange",
          "ConversationId": {"__type": "ItemId:#Exchange", "Id": conversation_id},
          "SyncState": "",
        }
      ],
      "ItemShape": {
        "__type": "ItemResponseShape:#Exchange",
        "BaseShape": "IdOnly",
        "AddBlankTargetToLinks": True,
        "BlockContentFromUnknownSenders": False,
        "BlockExternalImagesIfSenderUntrusted": True,
        "ClientSupportsIrm": True,
        "FilterHtmlContent": True,
        "FilterInlineSafetyTips": True,
        "MaximumBodySize": max_body_size,
        "MaximumRecipientsToReturn": 50,
        "ImageProxyCapability": "OwaAndConnectorsProxy",
        "AdditionalProperties": [
          {"__type": "PropertyUri:#Exchange", "FieldURI": "CanDelete"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "HasAttachments"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "NormalizedBody"},
          {"__type": "PropertyUri:#Exchange", "FieldURI": "TextBody"},
        ],
        "CalculateOnlyFirstBody": False,
        "BodyShape": "UniqueFragment",
      },
      "ShapeName": "ItemPart",
      "SortOrder": "DateOrderAscending",
      "MaxItemsToReturn": max_items,
      "Action": "ReturnRootNode",
      "ReturnSubmittedItems": True,
      "ReturnDeletedItems": True,
    },
  }


@dataclass(frozen=True)
class SearchQuery:
  query: str
  offset: int = 0
  limit: int = 25
  cvid: str | None = None
  logical_id: str | None = None


def search_query(search: SearchQuery, time_zone: str = DEFAULT_TIME_ZONE) -> dict[str, Any]:
  return {
    "Cvid": search.cvid,
    "Scenario": {"Name": "owa.react"},
    "TimeZone": time_zone,
    "TextDecorations": "Off",
    "EntityRequests": [
      {
        "EntityType": "Conversation",
        "ContentSources": ["Exchange"],
        "Filter": {
          "Or": [
            {"Term": {"DistinguishedFolderName": "msgfolderroot"}},
            {"Term": {"DistinguishedFolderName": "DeletedItems"}},
          ]
        },
        "From": search.offset,
        "Query": {"QueryString": search.query},
        "RefiningQueries": None,
        "Size": search.limit,
        "Sort": [
          {"Field": "Score", "SortDirection": "Desc", "Count": 7},
          {"Field": "Time", "SortDirection": "Desc"},
        ],
        "EnableTopResults": True,
        "TopResultsCount": min(7, search.limit),
      }
    ],
    "QueryAlterationOptions": {
      "EnableSuggestion": True,
      "EnableAlteration": True,
      "SupportedRecourseDisplayTypes": [
        "Suggestion",
        "NoResultModification",
        "NoResultFolderRefinerModification",
        "NoRequeryModification",
        "Modification",
      ],
    },
    "LogicalId": search.logical_id,
  }

