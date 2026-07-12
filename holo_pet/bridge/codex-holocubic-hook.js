#!/usr/bin/env node
"use strict";

const http = require("http");
const path = require("path");
const { spawn } = require("child_process");

const DEFAULT_STATUS_URL = "http://127.0.0.1:17321/event";
const REQUEST_TIMEOUT_MS = 400;
const MAX_STDIN_BYTES = 64 * 1024;

const EVENT_STATES = Object.freeze({
  SessionStart: "idle",
  UserPromptSubmit: "thinking",
  PreToolUse: "working",
  PermissionRequest: "notification",
  PostToolUse: "working",
  PreCompact: "working",
  PostCompact: "thinking",
  SubagentStart: "building",
  SubagentStop: "working",
  Stop: "done",
});

function clip(value, maxLength) {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(0, maxLength - 3))}...`;
}

function projectFromCwd(cwd) {
  const normalized = String(cwd || "").replace(/[\\/]+$/, "");
  if (!normalized) return "";
  return clip(normalized.split(/[\\/]/).pop() || path.basename(normalized), 40);
}

function displayTool(toolName) {
  const raw = clip(toolName, 64);
  if (!raw) return "";
  if (/^(Bash|shell_command)$/i.test(raw)) return "terminal";
  if (/^(apply_patch|Edit|Write)$/i.test(raw)) return "edit";
  if (/web|browser/i.test(raw)) return "web";
  if (/image/i.test(raw)) return "image";
  if (/mcp__/i.test(raw)) return clip(raw.replace(/^mcp__/, ""), 32);
  return clip(raw, 32);
}

function responseLooksFailed(response) {
  if (!response || typeof response !== "object") return false;
  if (response.is_error === true || response.isError === true || response.success === false) return true;
  const exitCode = response.exit_code ?? response.exitCode ?? response.code;
  return typeof exitCode === "number" && exitCode !== 0;
}

function buildStatus(payload) {
  const source = payload && typeof payload === "object" ? payload : {};
  const event = clip(source.hook_event_name, 48) || "Unknown";
  let state = EVENT_STATES[event] || "idle";
  if (event === "PostToolUse" && responseLooksFailed(source.tool_response)) state = "error";

  return {
    state,
    event,
    project: projectFromCwd(source.cwd),
    tool: displayTool(source.tool_name),
    session: clip(source.session_id, 80),
    model: clip(source.model, 32),
    subagent_id: clip(source.agent_id, 80),
    event_detail: clip(source.source || source.trigger || source.compact_trigger || source.agent_type, 32),
    sent_at: Date.now(),
  };
}

function readStdin() {
  return new Promise((resolve) => {
    const chunks = [];
    let size = 0;
    process.stdin.on("data", (chunk) => {
      size += chunk.length;
      if (size <= MAX_STDIN_BYTES) chunks.push(chunk);
    });
    process.stdin.on("end", () => {
      if (size > MAX_STDIN_BYTES) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
      } catch {
        resolve({});
      }
    });
    process.stdin.on("error", () => resolve({}));
    process.stdin.resume();
  });
}

function postStatus(status, statusUrl = process.env.HOLOCUBIC_STATUS_URL || DEFAULT_STATUS_URL) {
  return new Promise((resolve) => {
    let url;
    try {
      url = new URL(statusUrl);
    } catch {
      resolve(false);
      return;
    }

    const body = Buffer.from(JSON.stringify(status));
    const req = http.request({
      protocol: url.protocol,
      hostname: url.hostname,
      port: url.port || 80,
      method: "POST",
      path: `${url.pathname}${url.search}`,
      headers: {
        "content-type": "application/json",
        "content-length": body.length,
        "connection": "close",
        "x-holo-pet-hook": "codex",
      },
    }, (res) => {
      res.resume();
      res.on("end", () => resolve(res.statusCode >= 200 && res.statusCode < 300));
    });
    req.setTimeout(REQUEST_TIMEOUT_MS, () => req.destroy());
    req.on("error", () => resolve(false));
    req.end(body);
  });
}

function startLocalBridge() {
  try {
    const serverPath = path.join(__dirname, "codex-holocubic-server.js");
    const child = spawn(process.execPath, [serverPath], {
      detached: true,
      stdio: "ignore",
      windowsHide: true,
    });
    child.unref();
    return true;
  } catch {
    return false;
  }
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  const payload = await readStdin();
  const status = buildStatus(payload);
  let delivered = await postStatus(status);
  if (!delivered && !process.env.HOLOCUBIC_STATUS_URL && startLocalBridge()) {
    await delay(180);
    delivered = await postStatus(status);
  }
  // `{}` is valid for every registered Codex command hook and, importantly,
  // leaves PermissionRequest decisions to the native Codex approval UI.
  process.stdout.write("{}\n");
}

if (require.main === module) {
  main().catch(() => process.stdout.write("{}\n"));
}

module.exports = {
  DEFAULT_STATUS_URL,
  EVENT_STATES,
  buildStatus,
  displayTool,
  postStatus,
  projectFromCwd,
  responseLooksFailed,
  startLocalBridge,
};
