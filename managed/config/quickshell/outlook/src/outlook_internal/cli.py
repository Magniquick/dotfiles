from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path
from typing import Any

from .client import OutlookInternalClient
from .session import DEFAULT_SESSION_PATH, SessionSnapshot, capture_session


def print_json(value: Any) -> None:
  print(json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True))


def load_client(args: argparse.Namespace) -> OutlookInternalClient:
  snapshot = SessionSnapshot.from_file(args.session)
  if not getattr(args, "allow_stale", False):
    snapshot.assert_fresh()
  return OutlookInternalClient(snapshot)


def cmd_auth_status(args: argparse.Namespace) -> None:
  snapshot = SessionSnapshot.from_file(args.session)
  payload = snapshot.token_payload or {}
  print_json(
    {
      "session": str(args.session),
      "account": snapshot.account,
      "base_url": snapshot.base_url,
      "tenant_id": snapshot.tenant_id,
      "anchor": snapshot.x_anchormailbox,
      "captured_at": snapshot.captured_at,
      "token_upn": payload.get("upn") or payload.get("unique_name"),
      "token_audience": payload.get("aud"),
      "token_expires_in_seconds": snapshot.seconds_until_expiry(),
      "has_canary": bool(snapshot.x_owa_canary),
      "has_clientid": bool(snapshot.x_clientid),
      "inbox_folder_id": snapshot.inbox_folder_id,
      "root_folder_id": snapshot.root_folder_id,
      "search_folder_id": snapshot.search_folder_id,
    }
  )


def cmd_auth_refresh(args: argparse.Namespace) -> None:
  snapshot = asyncio.run(
    capture_session(
      path=args.session,
      login_url=args.login_url,
      headed=args.headed,
      profile_dir=args.profile_dir,
    )
  )
  print_json(
    {
      "session": str(args.session),
      "account": snapshot.account,
      "base_url": snapshot.base_url,
      "tenant_id": snapshot.tenant_id,
      "anchor": snapshot.x_anchormailbox,
      "captured_at": snapshot.captured_at,
      "token_expires_in_seconds": snapshot.seconds_until_expiry(),
      "has_canary": bool(snapshot.x_owa_canary),
      "inbox_folder_id": snapshot.inbox_folder_id,
      "root_folder_id": snapshot.root_folder_id,
      "search_folder_id": snapshot.search_folder_id,
    }
  )


def cmd_folders(args: argparse.Namespace) -> None:
  client = load_client(args)
  try:
    parent_folder_id = args.parent_folder_id or client.snapshot.root_folder_id
    if not parent_folder_id:
      raise SystemExit("No parent folder id. Run auth refresh or pass --parent-folder-id.")
    print_json(client.folders(parent_folder_id, max_entries=args.limit))
  finally:
    client.close()


def cmd_unread(args: argparse.Namespace) -> None:
  client = load_client(args)
  try:
    parent_folder_id = args.parent_folder_id or client.snapshot.root_folder_id
    if not parent_folder_id:
      raise SystemExit("No parent folder id. Run auth refresh or pass --parent-folder-id.")
    folders = client.folders(parent_folder_id, max_entries=args.limit)
    total = sum(v.get("unread_count") or 0 for v in folders)
    print_json({"total_unread": total, "folders": folders})
  finally:
    client.close()


def cmd_inbox(args: argparse.Namespace) -> None:
  client = load_client(args)
  try:
    folder_id = args.folder_id or client.snapshot.inbox_folder_id
    if not folder_id:
      raise SystemExit("No inbox folder id. Run auth refresh or pass --folder-id.")
    print_json(
      client.conversations(
        folder_id,
        search_folder_id=args.search_folder_id or client.snapshot.search_folder_id,
        offset=args.offset,
        limit=args.limit,
      )
    )
  finally:
    client.close()


def cmd_search(args: argparse.Namespace) -> None:
  client = load_client(args)
  try:
    result = client.search(args.query, offset=args.offset, limit=args.limit)
    if not args.raw:
      result.pop("raw", None)
      for row in result["results"]:
        row.pop("raw", None)
    print_json(result)
  finally:
    client.close()


def cmd_read(args: argparse.Namespace) -> None:
  client = load_client(args)
  try:
    result = client.read_conversation(args.conversation_id, max_items=args.limit)
    if not args.raw:
      result.pop("raw", None)
      for row in result["messages"]:
        row.pop("raw", None)
    print_json(result)
  finally:
    client.close()


def cmd_capture(args: argparse.Namespace) -> None:
  from .capture import run_capture

  asyncio.run(run_capture(args))


def build_parser() -> argparse.ArgumentParser:
  parser = argparse.ArgumentParser(description="Outlook Web internal API client")
  parser.add_argument("--session", type=Path, default=DEFAULT_SESSION_PATH)
  parser.add_argument("--allow-stale", action="store_true")
  sub = parser.add_subparsers(required=True)

  auth = sub.add_parser("auth")
  auth_sub = auth.add_subparsers(required=True)
  auth_status = auth_sub.add_parser("status")
  auth_status.set_defaults(func=cmd_auth_status)
  auth_refresh = auth_sub.add_parser("refresh")
  auth_refresh.add_argument(
    "--login-url",
    default="https://outlook.office.com/mail/?login_hint=navon.mitmpl2024%40learner.manipal.edu",
  )
  auth_refresh.add_argument("--headed", action="store_true")
  auth_refresh.add_argument(
    "--profile-dir",
    type=Path,
    default=Path.home() / ".cache" / "outlook-internal" / "playwright-profile",
  )
  auth_refresh.set_defaults(func=cmd_auth_refresh)

  folders = sub.add_parser("folders")
  folders.add_argument(
    "--parent-folder-id",
    required=False,
    help="Root or msgfolderroot folder id. Capture output documents the current value.",
  )
  folders.add_argument("--limit", type=int, default=100)
  folders.set_defaults(func=cmd_folders)

  unread = sub.add_parser("unread")
  unread.add_argument("--parent-folder-id")
  unread.add_argument("--limit", type=int, default=100)
  unread.set_defaults(func=cmd_unread)

  inbox = sub.add_parser("inbox")
  inbox.add_argument("--folder-id", help="Inbox folder id from FindConversation/FindFolder.")
  inbox.add_argument("--search-folder-id")
  inbox.add_argument("--offset", type=int, default=0)
  inbox.add_argument("--limit", type=int, default=25)
  inbox.set_defaults(func=cmd_inbox)

  search = sub.add_parser("search")
  search.add_argument("query")
  search.add_argument("--offset", type=int, default=0)
  search.add_argument("--limit", type=int, default=25)
  search.add_argument("--raw", action="store_true")
  search.set_defaults(func=cmd_search)

  read = sub.add_parser("read")
  read.add_argument("conversation_id")
  read.add_argument("--limit", type=int, default=20)
  read.add_argument("--raw", action="store_true")
  read.set_defaults(func=cmd_read)

  capture = sub.add_parser("capture")
  capture.add_argument("--query")
  capture.add_argument("--headed", action="store_true")
  capture.add_argument("--raw", action="store_true")
  capture.add_argument("--out-dir", type=Path, default=Path("examples/captures"))
  capture.add_argument(
    "--profile-dir",
    type=Path,
    default=Path.home() / ".cache" / "outlook-internal" / "playwright-profile",
  )
  capture.set_defaults(func=cmd_capture)

  return parser


def main() -> None:
  parser = build_parser()
  args = parser.parse_args()
  args.func(args)


if __name__ == "__main__":
  main()
