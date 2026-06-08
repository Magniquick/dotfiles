from __future__ import annotations

import argparse
import base64
import json
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote

DEFAULT_ACCOUNT = "navon.mitmpl2024@learner.manipal.edu"
DEFAULT_LOGIN_URL = (
  "https://outlook.office.com/mail/?login_hint="
  + quote(DEFAULT_ACCOUNT, safe="")
)
DEFAULT_SESSION_PATH = Path(__file__).resolve().parents[2] / ".secrets" / "session.json"
DEFAULT_PROFILE_DIR = Path.home() / ".cache" / "outlook-internal" / "playwright-profile"


def utc_now_iso() -> str:
  return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _b64url_json(segment: str) -> dict[str, Any]:
  padded = segment + "=" * (-len(segment) % 4)
  return json.loads(base64.urlsafe_b64decode(padded.encode("ascii")))


def decode_jwt_payload(authorization: str | None) -> dict[str, Any]:
  if not authorization:
    return {}
  token = authorization.removeprefix("Bearer ").strip()
  parts = token.split(".")
  if len(parts) < 2:
    return {}
  try:
    return _b64url_json(parts[1])
  except Exception:
    return {}


@dataclass
class SessionSnapshot:
  base_url: str
  login_url: str
  account: str
  authorization: str
  x_anchormailbox: str
  x_owa_sessionid: str
  x_owa_canary: str | None = None
  tenant_id: str | None = None
  x_client_version: str | None = None
  x_clientid: str | None = None
  inbox_folder_id: str | None = None
  root_folder_id: str | None = None
  search_folder_id: str | None = None
  owa_app_id: str = "9199bf20-a13f-4107-85dc-02114787ef48"
  captured_at: str = ""
  token_payload: dict[str, Any] | None = None

  @classmethod
  def from_file(cls, path: Path = DEFAULT_SESSION_PATH) -> "SessionSnapshot":
    data = json.loads(path.read_text())
    return cls.from_dict(data)

  @classmethod
  def from_dict(cls, data: dict[str, Any]) -> "SessionSnapshot":
    authorization = data.get("authorization", "")
    token_payload = data.get("token_payload") or decode_jwt_payload(authorization)
    return cls(
      base_url=data.get("base_url", "https://outlook.cloud.microsoft").rstrip("/"),
      login_url=data.get("login_url", DEFAULT_LOGIN_URL),
      account=data.get("account", DEFAULT_ACCOUNT),
      authorization=authorization,
      x_anchormailbox=data.get("x_anchormailbox") or data.get("puid_anchor", ""),
      x_owa_sessionid=data.get("x_owa_sessionid", ""),
      x_owa_canary=data.get("x_owa_canary"),
      tenant_id=data.get("tenant_id") or token_payload.get("tid"),
      x_client_version=data.get("x_client_version"),
      x_clientid=data.get("x_clientid"),
      inbox_folder_id=data.get("inbox_folder_id"),
      root_folder_id=data.get("root_folder_id"),
      search_folder_id=data.get("search_folder_id"),
      owa_app_id=data.get("owa_app_id", "9199bf20-a13f-4107-85dc-02114787ef48"),
      captured_at=data.get("captured_at", ""),
      token_payload=token_payload,
    )

  def to_dict(self) -> dict[str, Any]:
    payload = self.token_payload or decode_jwt_payload(self.authorization)
    return {
      "base_url": self.base_url,
      "login_url": self.login_url,
      "account": self.account,
      "tenant_id": self.tenant_id or payload.get("tid"),
      "puid_anchor": self.x_anchormailbox,
      "x_anchormailbox": self.x_anchormailbox,
      "authorization": self.authorization,
      "x_owa_canary": self.x_owa_canary,
      "x_owa_sessionid": self.x_owa_sessionid,
      "x_client_version": self.x_client_version,
      "x_clientid": self.x_clientid,
      "inbox_folder_id": self.inbox_folder_id,
      "root_folder_id": self.root_folder_id,
      "search_folder_id": self.search_folder_id,
      "owa_app_id": self.owa_app_id,
      "captured_at": self.captured_at or utc_now_iso(),
      "token_payload": payload,
    }

  @property
  def token_exp(self) -> int | None:
    payload = self.token_payload or decode_jwt_payload(self.authorization)
    exp = payload.get("exp")
    return int(exp) if isinstance(exp, int | float) else None

  def seconds_until_expiry(self) -> int | None:
    if self.token_exp is None:
      return None
    return self.token_exp - int(time.time())

  def assert_fresh(self, min_seconds: int = 300) -> None:
    remaining = self.seconds_until_expiry()
    if remaining is not None and remaining < min_seconds:
      raise RuntimeError(
        f"Outlook bearer token expires in {remaining}s. Run: uv run outlook-internal auth refresh"
      )

  def write(self, path: Path = DEFAULT_SESSION_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n")


async def capture_session(
  path: Path = DEFAULT_SESSION_PATH,
  login_url: str = DEFAULT_LOGIN_URL,
  headed: bool = False,
  profile_dir: Path = DEFAULT_PROFILE_DIR,
  timeout_ms: int = 90_000,
) -> SessionSnapshot:
  from playwright.async_api import async_playwright

  captured: dict[str, Any] = {}

  profile_dir.mkdir(parents=True, exist_ok=True)
  async with async_playwright() as p:
    context = await p.chromium.launch_persistent_context(
      str(profile_dir),
      headless=not headed,
      viewport={"width": 1400, "height": 1000},
    )
    page = context.pages[0] if context.pages else await context.new_page()

    async def on_request(request: Any) -> None:
      url = request.url
      if "outlook.cloud.microsoft" not in url:
        return
      if not (
        "service.svc" in url
        or "searchservice/api/v2/query" in url
        or "startupdata.ashx" in url
      ):
        return
      headers = request.headers
      _extract_folder_ids(captured, request.post_data, headers.get("x-owa-urlpostdata"))
      authorization = headers.get("authorization")
      anchor = headers.get("x-anchormailbox")
      session_id = headers.get("x-owa-sessionid")
      if authorization and anchor and session_id:
        captured.update(
          {
            "base_url": "https://outlook.cloud.microsoft",
            "login_url": login_url,
            "account": DEFAULT_ACCOUNT,
            "authorization": authorization,
            "x_anchormailbox": anchor,
            "x_owa_sessionid": session_id,
            "x_owa_canary": headers.get("x-owa-canary"),
            "x_client_version": headers.get("x-client-version"),
            "x_clientid": headers.get("x-clientid"),
            "owa_app_id": headers.get("owaappid", "9199bf20-a13f-4107-85dc-02114787ef48"),
            "captured_at": utc_now_iso(),
          }
        )

    page.on("request", on_request)
    await page.goto(login_url, wait_until="domcontentloaded")
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline and not captured.get("authorization"):
      await page.wait_for_timeout(1000)
      if "login.microsoftonline.com" in page.url or "login.live.com" in page.url:
        if not headed:
          await context.close()
          raise RuntimeError("Interactive Microsoft login required. Retry with --headed.")
      if "outlook.cloud.microsoft" in page.url:
        await page.evaluate("() => window.scrollBy(0, 1)")

    if not captured.get("authorization"):
      storage_snapshot = await _capture_storage_snapshot(page, login_url)
      captured.update({key: value for key, value in storage_snapshot.items() if value})
    if not captured.get("authorization"):
      await context.close()
      raise RuntimeError("Timed out before capturing Outlook auth. Retry with --headed.")

    snapshot = SessionSnapshot.from_dict(captured)
    # Search often carries the canary. Trigger one cheap search if the list calls did not expose it.
    if not snapshot.x_owa_canary:
      try:
        search = page.locator('input[aria-label="Search for email, meetings, files and more."]').first()
        await search.click(timeout=3000)
        await search.fill("isread:no", timeout=3000)
        await page.keyboard.press("Enter")
        await page.wait_for_timeout(5000)
        snapshot = SessionSnapshot.from_dict(captured)
      except Exception:
        pass

    await context.close()
    snapshot.write(path)
    return snapshot


def _extract_folder_ids(
  captured: dict[str, Any],
  post_data: str | None,
  encoded_header_body: str | None,
) -> None:
  text = post_data
  if not text and encoded_header_body:
    text = unquote(encoded_header_body)
  if not text:
    return
  try:
    data = json.loads(text)
  except json.JSONDecodeError:
    return
  body = data.get("Body", {})
  parent = (
    body.get("ParentFolderId", {})
    .get("BaseFolderId", {})
    .get("Id")
  )
  if parent and data.get("__type", "").startswith("FindConversation"):
    captured.setdefault("inbox_folder_id", parent)
  search = body.get("SearchFolderId", {}).get("Id")
  if search:
    captured.setdefault("search_folder_id", search)
  parents = body.get("ParentFolderIds")
  if isinstance(parents, list) and parents:
    root = parents[0].get("Id") if isinstance(parents[0], dict) else None
    if root and data.get("__type", "").startswith("FindFolder"):
      captured.setdefault("root_folder_id", root)


async def _capture_storage_snapshot(page: Any, login_url: str) -> dict[str, Any]:
  data = await page.evaluate(
    """() => {
      const tokenRows = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        const value = localStorage.getItem(key);
        if (!key || !value || !key.includes('accesstoken')) continue;
        try {
          const parsed = JSON.parse(value);
          const target = `${parsed.target || ''} ${key}`.toLowerCase();
          if (
            target.includes('https://outlook.office.com') &&
            (target.includes('mail.readwrite') || target.includes('owa.accessasuser'))
          ) {
            tokenRows.push({key, parsed});
          }
        } catch (_) {}
      }
      const best = tokenRows.sort((a, b) => (b.parsed.expiresOn || 0) - (a.parsed.expiresOn || 0))[0];
      return {
        token: best?.parsed?.secret || null,
        account: JSON.parse(localStorage.getItem('sessionTracking_10032003b5c6fbdc') || '{}')?.upn || null,
        clientId: localStorage.getItem('olk-OwaClientId') || null,
        canary: document.cookie.split('; ').find(v => v.startsWith('X-OWA-CANARY='))?.split('=').slice(1).join('=') || null
      };
    }"""
  )
  token = data.get("token")
  if not token:
    return {}
  payload = decode_jwt_payload(f"Bearer {token}")
  tenant_id = payload.get("tid")
  puid = payload.get("puid")
  anchor = f"PUID:{puid}@{tenant_id}" if puid and tenant_id else ""
  return {
    "base_url": "https://outlook.cloud.microsoft",
    "login_url": login_url,
    "account": data.get("account") or payload.get("upn") or DEFAULT_ACCOUNT,
    "authorization": f"Bearer {token}",
    "x_anchormailbox": anchor,
    "x_owa_sessionid": str(uuid.uuid4()),
    "x_owa_canary": data.get("canary"),
    "x_clientid": data.get("clientId"),
    "tenant_id": tenant_id,
    "owa_app_id": "9199bf20-a13f-4107-85dc-02114787ef48",
    "captured_at": utc_now_iso(),
  }


def add_auth_args(parser: argparse.ArgumentParser) -> None:
  parser.add_argument("--session", type=Path, default=DEFAULT_SESSION_PATH)
  parser.add_argument("--allow-stale", action="store_true")


def new_request_id() -> str:
  return str(uuid.uuid4())
