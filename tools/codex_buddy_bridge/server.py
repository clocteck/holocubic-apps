#!/usr/bin/env python3
import argparse
import json
import os
import re
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


TAIL_BYTES_DEFAULT = 2 * 1024 * 1024
RECENT_COMPLETE_SECONDS = 12
RECENT_ERROR_SECONDS = 90


def clamp_pct(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if n < 0:
        return 0
    if n > 100:
        return 100
    return int(round(n))


def parse_ts(value):
    if not value:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    try:
        text = str(value)
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        return datetime.fromisoformat(text).timestamp()
    except Exception:
        return 0.0


def compact_text(value, limit=96):
    if value is None:
        return ""
    text = re.sub(r"\s+", " ", str(value)).strip()
    if len(text) <= limit:
        return text
    return text[: max(0, limit - 1)] + "..."


def decode_args(value):
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value:
        return {}
    try:
        decoded = json.loads(value)
        return decoded if isinstance(decoded, dict) else {}
    except Exception:
        return {}


def read_jsonl_tail(path, limit_bytes):
    size = path.stat().st_size
    with path.open("rb") as f:
        if size > limit_bytes:
            f.seek(size - limit_bytes)
            f.readline()
        raw = f.read()

    events = []
    for line in raw.decode("utf-8", errors="replace").splitlines():
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def tail_unique(values, count):
    seen = set()
    out = []
    for value in reversed(values):
        if not value or value in seen:
            continue
        seen.add(value)
        out.append(value)
        if len(out) >= count:
            break
    out.reverse()
    return out


class CodexSessionReader:
    def __init__(self, codex_home=None, tail_bytes=TAIL_BYTES_DEFAULT, state_file=None):
        self.codex_home = Path(codex_home or os.environ.get("CODEX_HOME") or Path.home() / ".codex")
        self.sessions_dir = self.codex_home / "sessions"
        self.tail_bytes = int(tail_bytes)
        self.state_file = Path(state_file) if state_file else None
        self.manual_state = {}
        self.last_permission = None
        self.seq = 0

    def load_manual_state(self):
        if not self.state_file:
            self.manual_state = {}
            return
        if not self.state_file.exists():
            self.manual_state = {}
            return
        try:
            self.manual_state = json.loads(self.state_file.read_text(encoding="utf-8"))
        except Exception as exc:
            self.manual_state = {
                "event": "error",
                "msg": f"state file error: {exc}",
                "pet": {"state": "dizzy", "text": "state file error"},
            }

    def latest_session_file(self):
        if not self.sessions_dir.exists():
            return None
        latest = None
        latest_mtime = -1.0
        for path in self.sessions_dir.rglob("*.jsonl"):
            try:
                mtime = path.stat().st_mtime
            except OSError:
                continue
            if mtime > latest_mtime:
                latest = path
                latest_mtime = mtime
        return latest

    def snapshot(self):
        self.seq += 1
        self.load_manual_state()
        now = time.time()
        path = self.latest_session_file()
        if not path:
            data = self.empty_snapshot("No Codex session", now)
            data.update(self.manual_state)
            return data

        try:
            events = read_jsonl_tail(path, self.tail_bytes)
            data = self.build_snapshot(path, events, now)
        except Exception as exc:
            data = self.empty_snapshot(f"Codex state read error: {exc}", now)
            data["event"] = "error"
            data["error"] = str(exc)
            data["pet"] = {"state": "dizzy", "text": "read error"}

        data.update(self.manual_state)
        if self.last_permission:
            data["last_permission"] = self.last_permission
        return data

    def empty_snapshot(self, message, now):
        return {
            "seq": self.seq,
            "total": 0,
            "running": 0,
            "waiting": 0,
            "msg": message,
            "entries": [],
            "tokens_today": None,
            "tokens": None,
            "quota_pct": None,
            "quota_5h_pct": None,
            "quota_7d_pct": None,
            "cost_today": None,
            "cost_month": None,
            "prompt": None,
            "pet": {"state": "sleep", "text": "no codex"},
            "updated_at": int(now),
            "source": {
                "type": "codex_session_jsonl",
                "codex_home": str(self.codex_home),
                "session": None,
            },
        }

    def build_snapshot(self, path, events, now):
        active_task = False
        start_ts = 0.0
        complete_ts = 0.0
        abort_ts = 0.0
        error_ts = 0.0
        last_ts = path.stat().st_mtime
        last_error = ""
        last_abort = ""
        last_agent_message = ""
        last_user_message = ""
        entries = []
        pending_calls = {}
        rate_limits = {}
        token_info = {}
        meta = {}
        turn = {}

        for event in events:
            ts = parse_ts(event.get("timestamp")) or last_ts
            if ts > last_ts:
                last_ts = ts

            typ = event.get("type")
            payload = event.get("payload") or {}
            if not isinstance(payload, dict):
                payload = {}

            if typ == "session_meta":
                meta.update(payload)
                continue

            if typ == "turn_context":
                turn.update(payload)
                continue

            ptyp = payload.get("type")
            if typ == "event_msg":
                if ptyp == "task_started":
                    active_task = True
                    start_ts = ts
                    entries.append("task started")
                elif ptyp == "task_complete":
                    active_task = False
                    complete_ts = ts
                    pending_calls.clear()
                    entries.append("task complete")
                elif ptyp == "turn_aborted":
                    active_task = False
                    abort_ts = ts
                    last_abort = compact_text(payload.get("reason") or "interrupted")
                    pending_calls.clear()
                    entries.append("turn aborted")
                elif ptyp == "error":
                    active_task = False
                    error_ts = ts
                    last_error = compact_text(payload.get("message") or "Codex error", 120)
                    entries.append("error: " + compact_text(last_error, 80))
                elif ptyp == "token_count":
                    rate_limits = payload.get("rate_limits") or {}
                    token_info = payload.get("info") or {}
                elif ptyp == "agent_message":
                    last_agent_message = compact_text(payload.get("message"), 110)
                    if last_agent_message:
                        entries.append(last_agent_message)
                elif ptyp == "user_message":
                    last_user_message = compact_text(payload.get("message"), 110)
                continue

            if typ != "response_item":
                continue

            if ptyp in ("function_call", "custom_tool_call"):
                call_id = payload.get("call_id") or ""
                name = payload.get("name") or "tool"
                args = decode_args(payload.get("arguments") or payload.get("input"))
                raw_args = json.dumps(args, ensure_ascii=False).lower()
                command = compact_text(args.get("command") or args.get("input") or payload.get("input") or name, 80)
                needs_approval = (
                    "require_escalated" in raw_args
                    or args.get("sandbox_permissions") == "require_escalated"
                )
                if call_id:
                    pending_calls[call_id] = {
                        "id": call_id,
                        "tool": name,
                        "hint": command,
                        "needs_approval": needs_approval,
                        "ts": ts,
                    }
                if name:
                    entries.append(f"{name}: {command}" if command and command != name else name)
                continue

            if ptyp in ("function_call_output", "custom_tool_call_output"):
                call_id = payload.get("call_id") or ""
                if call_id and call_id in pending_calls:
                    del pending_calls[call_id]
                output = payload.get("output") or ""
                if isinstance(output, str) and "Exit code:" in output:
                    first_line = compact_text(output.splitlines()[0], 80)
                    entries.append(first_line)
                continue

            if ptyp == "message":
                text = self.extract_message_text(payload)
                if text:
                    entries.append(text)

        primary = rate_limits.get("primary") or {}
        secondary = rate_limits.get("secondary") or {}
        quota_5h = self.remaining_percent(primary)
        quota_7d = self.remaining_percent(secondary)
        total_usage = token_info.get("total_token_usage") or {}
        last_usage = token_info.get("last_token_usage") or {}
        total_tokens = total_usage.get("total_tokens")
        last_tokens = last_usage.get("total_tokens")

        approval_prompt = self.find_approval_prompt(pending_calls)
        waiting = 1 if approval_prompt else 0
        running = 1 if active_task and not waiting else 0
        age_seconds = max(0, int(now - last_ts))

        recent_error = error_ts > 0 and (now - error_ts) <= RECENT_ERROR_SECONDS
        recent_abort = abort_ts > 0 and (now - abort_ts) <= RECENT_ERROR_SECONDS
        recent_complete = complete_ts > 0 and (now - complete_ts) <= RECENT_COMPLETE_SECONDS
        limit_reached = bool(rate_limits.get("rate_limit_reached_type"))

        pet_state = "idle"
        pet_text = "idle"
        msg = "Codex is idle"
        event = "idle"

        if waiting:
            pet_state = "attention"
            pet_text = "approval"
            msg = "Codex is waiting for shell approval"
            event = "waiting"
        elif running:
            pet_state = "busy"
            pet_text = "working"
            msg = "Codex is working"
            event = "running"
        elif recent_error or limit_reached:
            pet_state = "dizzy"
            pet_text = "error"
            msg = "Codex error"
            event = "error"
        elif recent_abort:
            pet_state = "dizzy"
            pet_text = "interrupted"
            msg = "Codex interrupted"
            event = "aborted"
        elif recent_complete:
            pet_state = "celebrate"
            pet_text = "done"
            msg = "Codex complete"
            event = "complete"
        elif quota_5h is not None and quota_7d is not None and quota_5h >= 80 and quota_7d >= 80:
            pet_state = "heart"
            pet_text = "healthy"

        if recent_error and last_error:
            msg = compact_text(last_error, 90)
        elif limit_reached:
            msg = compact_text(str(rate_limits.get("rate_limit_reached_type")), 90)

        data = {
            "seq": self.seq,
            "total": 1,
            "running": running,
            "waiting": waiting,
            "msg": msg,
            "entries": tail_unique(entries, 5),
            "tokens_today": total_tokens,
            "tokens": total_tokens,
            "last_tokens": last_tokens,
            "quota_pct": quota_5h,
            "quota_5h_pct": quota_5h,
            "quota_7d_pct": quota_7d,
            "quota_5h_resets_at": primary.get("resets_at"),
            "quota_7d_resets_at": secondary.get("resets_at"),
            "cost_today": None,
            "cost_month": None,
            "prompt": approval_prompt,
            "pet": {
                "state": pet_state,
                "text": pet_text,
            },
            "event": event,
            "error": last_error if recent_error else None,
            "last_agent_message": last_agent_message,
            "last_user_message": last_user_message,
            "updated_at": int(now),
            "source": {
                "type": "codex_session_jsonl",
                "codex_home": str(self.codex_home),
                "session": str(path),
                "session_mtime": int(path.stat().st_mtime),
                "age_seconds": age_seconds,
                "cwd": meta.get("cwd") or turn.get("cwd"),
                "model": meta.get("model") or turn.get("model"),
                "approval_policy": turn.get("approval_policy"),
                "plan_type": rate_limits.get("plan_type"),
                "rate_limit_id": rate_limits.get("limit_id"),
            },
        }
        return data

    def remaining_percent(self, bucket):
        if not isinstance(bucket, dict):
            return None
        used = clamp_pct(bucket.get("used_percent"))
        if used is None:
            return None
        return clamp_pct(100 - used)

    def find_approval_prompt(self, pending_calls):
        for call in sorted(pending_calls.values(), key=lambda item: item.get("ts", 0)):
            if not call.get("needs_approval"):
                continue
            return {
                "id": call.get("id"),
                "tool": call.get("tool") or "shell",
                "hint": call.get("hint") or "Allow command?",
            }
        return None

    def extract_message_text(self, payload):
        content = payload.get("content")
        if isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict):
                    parts.append(item.get("text") or item.get("input_text") or "")
            return compact_text(" ".join(parts), 110)
        return compact_text(payload.get("message") or payload.get("text"), 110)

    def record_permission(self, payload):
        self.last_permission = {
            "id": payload.get("id"),
            "decision": payload.get("decision"),
            "at": int(time.time()),
            "applied": False,
            "reason": "VSCode Codex does not expose an external approval API here",
        }


class Handler(BaseHTTPRequestHandler):
    state = CodexSessionReader()

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))

    def send_json(self, status, value):
        raw = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("access-control-allow-origin", "*")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/state":
            self.send_json(200, self.state.snapshot())
            return
        if path == "/health":
            self.send_json(200, {"ok": True, "codex_home": str(self.state.codex_home)})
            return
        self.send_json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("content-length") or "0")
        raw = self.rfile.read(length).decode("utf-8") if length else "{}"
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError as exc:
            self.send_json(400, {"ok": False, "error": str(exc)})
            return
        if path == "/permission":
            decision = payload.get("decision")
            if decision not in ("once", "approve", "deny"):
                self.send_json(400, {"ok": False, "error": "decision must be once, approve, or deny"})
                return
            self.state.record_permission(payload)
            print("permission:", self.state.last_permission)
            self.send_json(
                200,
                {
                    "ok": True,
                    "applied": False,
                    "reason": self.state.last_permission["reason"],
                },
            )
            return
        self.send_json(404, {"ok": False, "error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("access-control-allow-origin", "*")
        self.send_header("access-control-allow-methods", "GET, POST, OPTIONS")
        self.send_header("access-control-allow-headers", "content-type")
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description="Codex Buddy bridge server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8788)
    parser.add_argument("--codex-home", default=None, help="Codex home directory, defaults to %%CODEX_HOME%% or ~/.codex")
    parser.add_argument("--tail-bytes", type=int, default=TAIL_BYTES_DEFAULT)
    parser.add_argument("--state-file", default=None, help="Optional JSON file merged into /state")
    args = parser.parse_args()

    Handler.state = CodexSessionReader(
        codex_home=args.codex_home,
        tail_bytes=args.tail_bytes,
        state_file=args.state_file,
    )
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Codex Buddy bridge listening on http://{args.host}:{args.port}")
    print("Device default: http://192.168.0.80:8788")
    print(f"Codex home: {Handler.state.codex_home}")
    server.serve_forever()


if __name__ == "__main__":
    main()
