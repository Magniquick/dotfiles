#!/usr/bin/env -S uv run --script
#
# /// script
# requires-python = ">=3.12"
# dependencies = [
# 	"arrow",
# 	"google-api-python-client",
# 	"google-auth-oauthlib",
# ]
# [tool.uv]
# exclude-newer = "2025-11-08T00:00:00Z"
# ///

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

import arrow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build

# If modifying these scopes, delete the file token.json.
SCOPES = ["https://www.googleapis.com/auth/tasks.readonly"]


def get_unix_timestamp(date_str: str | None) -> float:
    if date_str is None:
        return float("inf")
    dt = datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.%fZ")

    # Set the timezone to UTC
    dt = dt.replace(tzinfo=timezone.utc)

    # Convert to Unix timestamp
    unix_timestamp = dt.timestamp()
    return unix_timestamp

xdg_cache_home = os.environ.get("XDG_CACHE_HOME")
cache_root = Path(xdg_cache_home) if xdg_cache_home else Path.home() / ".cache"
cache = cache_root / "waybar-google-tasks"
cache.mkdir(parents=True, exist_ok=True)
token_path = cache / "token.json"
root = Path(__file__).resolve().parent
credentials_path = root / "credentials.json"

assert credentials_path.exists(), f"credentials.json not found in {root}; see https://developers.google.com/workspace/tasks/quickstart/python"

def get_tasks() -> list:
    creds = None
    # The file token.json stores the user's access and refresh tokens, and is
    # created automatically when the authorization flow completes for the first
    # time.
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(token_path, SCOPES)
    # If there are no (valid) credentials available, let the user log in.
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            creds.refresh(Request())
        else:
            flow = InstalledAppFlow.from_client_secrets_file(credentials_path, SCOPES)
            creds = flow.run_local_server(port=0)
    # Save the credentitals for the next run
    with open(token_path, "w") as token:
        token.write(creds.to_json())

    service = build("tasks", "v1", credentials=creds)

    # Call the Tasks API
    results = service.tasklists().list(maxResults=10).execute()
    items = results.get("items", [])
    if not items:
        return []

    tasks_items: List[Dict] = list()
    for item in items:
        if item["title"] == "My Tasks":
            tasklist_id = item["id"]
            tasks = service.tasks().list(tasklist=tasklist_id).execute()
            tasks_items = tasks.get("items", [])
            if not tasks_items:
                return []

    to_do_tasks = list()
    for task in tasks_items:
        if task["status"] == "needsAction":
            to_do_tasks.append(
                (task["title"], get_unix_timestamp(task.get("due")), get_unix_timestamp(task.get("updated")))
            )

    # print("To Do Tasks:")
    # for item in to_do_tasks:
    #     print(f"Task: {item[0]}, Due: {item[1]}, Updated: {item[2]}")

    # Sort the tasks by due date
    return sorted(to_do_tasks, key=lambda x: (x[1], x[2]))


def humanise(timestamp: float) -> str | None:
    """convert unix timestamp to human-readable format"""
    if timestamp == float("inf") or not timestamp:
        return None
    dt = arrow.get(timestamp, tzinfo=timezone.utc)
    return dt.humanize()


def waybar_format(tasks: list) -> str:
    """pretty-print remaining tasks"""
    if not tasks:
        return " No pending tasks :D"

    output = ""
    for i in tasks:
        title = i[0]
        due = humanise(i[1])
        if due:
            output += f"• {title} (up {due})\n"
        else:
            output += f"• {title}\n"

    return output.strip()


def json_format(tasks: str) -> str:
    """format tasks as json for waybar"""
    import json

    output = {"text": "", "tooltip": tasks}

    return json.dumps(output)


if __name__ == "__main__":
    # try:
    tasks = get_tasks()
    output = waybar_format(tasks)
    output = "<big>Google To-Do Tasks:</big>\n" + output
    # except Exception as e:
    # 	output = "  Error fetching tasks !"
    json_output = json_format(output)
    print(json_output, end="")
