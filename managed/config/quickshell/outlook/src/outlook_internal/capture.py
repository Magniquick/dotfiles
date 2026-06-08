from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TOKENISH = ("authorization", "cookie", "token", "canary", "x-owa-canary")


def redact_headers(headers: dict[str, str], raw: bool = False) -> dict[str, str]:
  if raw:
    return dict(headers)
  return {
    key: ("<redacted>" if any(part in key.lower() for part in TOKENISH) else value)
    for key, value in headers.items()
  }


def stamp() -> str:
  return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


async def run_capture(args: Any) -> None:
  from playwright.async_api import async_playwright

  args.out_dir.mkdir(parents=True, exist_ok=True)
  output = args.out_dir / f"outlook-capture-{stamp()}.jsonl"
  rows: list[dict[str, Any]] = []

  async with async_playwright() as p:
    context = await p.chromium.launch_persistent_context(
      str(args.profile_dir),
      headless=not args.headed,
      viewport={"width": 1400, "height": 1000},
    )
    page = context.pages[0] if context.pages else await context.new_page()

    async def on_request_finished(request: Any) -> None:
      url = request.url
      if not (
        "service.svc" in url
        or "searchservice/api/v2/query" in url
        or "startupdata.ashx" in url
      ):
        return
      post_data = request.post_data
      row = {
        "method": request.method,
        "url": url,
        "headers": redact_headers(request.headers, raw=args.raw),
        "post_data": post_data,
      }
      try:
        response = await request.response()
        row["status"] = response.status if response else None
      except Exception:
        row["status"] = None
      rows.append(row)

    page.on("requestfinished", on_request_finished)
    await page.goto(
      "https://outlook.office.com/mail/?login_hint=navon.mitmpl2024%40learner.manipal.edu",
      wait_until="domcontentloaded",
    )
    await page.wait_for_timeout(6000)
    if args.query:
      search = page.locator('input[aria-label="Search for email, meetings, files and more."]').first()
      await search.click()
      await search.fill(args.query)
      await page.keyboard.press("Enter")
      await page.wait_for_timeout(9000)
    await context.close()

  with output.open("w") as handle:
    for row in rows:
      handle.write(json.dumps(row, ensure_ascii=False) + "\n")
  print(output)
