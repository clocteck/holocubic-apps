#!/usr/bin/env node
"use strict";

const http = require("http");
const fs = require("fs");
const os = require("os");
const path = require("path");

const HOST = process.env.HOLOCUBIC_BRIDGE_HOST || "0.0.0.0";
const PORT = Number(process.env.HOLOCUBIC_BRIDGE_PORT || 17321);
const MAX_BODY = 64 * 1024;
const MAX_SESSION_TAIL = 8 * 1024 * 1024;
const HISTORY_LIMIT = 6;
const CODEX_HOME = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const SESSIONS_DIR = path.join(CODEX_HOME, "sessions");
const clients = new Set();

let sessionActivity = {
  history: [],
  tool_count: 0,
  error_count: 0,
  started_at: 0,
};
const activeSubagents = new Set();

function activitySnapshot() {
  return {
    history: sessionActivity.history.slice(-HISTORY_LIMIT),
    tool_count: sessionActivity.tool_count,
    error_count: sessionActivity.error_count,
    subagent_count: activeSubagents.size,
    started_at: sessionActivity.started_at,
  };
}

let status = {
  state: "idle",
  event: "BridgeStart",
  project: "holocubic",
  tool: "",
  session: "",
  model: "",
  effort: "",
  context: null,
  subagent_id: "",
  sent_at: Date.now(),
  usage: null,
  activity: activitySnapshot(),
  source: "bridge",
};

let lastHookAt = 0;
let logCursor = null;
let postToolResumeTimer = null;

function resetActivity(eventAt) {
  sessionActivity = {
    history: [],
    tool_count: 0,
    error_count: 0,
    started_at: eventAt,
  };
  activeSubagents.clear();
}

function trackActivity(incoming, eventAt) {
  const event = String(incoming.event || "");
  if (!event || event === "BridgeStart") return false;

  if (event === "UserPromptSubmit" || event === "event_msg:task_started" || event === "SessionStart") {
    resetActivity(eventAt);
  } else if (!sessionActivity.started_at) {
    sessionActivity.started_at = eventAt;
  }

  const tool = String(incoming.tool || "");
  const state = String(incoming.state || "idle");
  const previous = sessionActivity.history[sessionActivity.history.length - 1];
  const duplicate = previous
    && previous.event === event
    && previous.tool === tool
    && previous.state === state
    && Math.abs(eventAt - previous.at) < 250;
  if (duplicate) return false;

  if (event === "PreToolUse" || event === "response_item:function_call" || event === "response_item:custom_tool_call") {
    sessionActivity.tool_count += 1;
  }
  if (state === "error") sessionActivity.error_count += 1;
  if (event === "SubagentStart" && incoming.subagent_id) activeSubagents.add(String(incoming.subagent_id));
  if (event === "SubagentStop" && incoming.subagent_id) activeSubagents.delete(String(incoming.subagent_id));

  sessionActivity.history.push({ event, tool, state, at: eventAt });
  if (sessionActivity.history.length > HISTORY_LIMIT) {
    sessionActivity.history.splice(0, sessionActivity.history.length - HISTORY_LIMIT);
  }
  return true;
}

const LOG_EVENT_STATES = Object.freeze({
  "event_msg:task_started": "thinking",
  "event_msg:user_message": "thinking",
  "event_msg:guardian_assessment": "working",
  "event_msg:exec_command_end": "working",
  "event_msg:patch_apply_end": "working",
  "event_msg:custom_tool_call_output": "working",
  "response_item:function_call": "working",
  "response_item:custom_tool_call": "working",
  "response_item:web_search_call": "working",
  "event_msg:task_complete": "done",
  "event_msg:context_compacted": "working",
  "event_msg:turn_aborted": "idle",
});

function projectFromCwd(cwd) {
  const normalized = String(cwd || "").replace(/[\\/]+$/, "");
  return normalized ? normalized.split(/[\\/]/).pop().slice(0, 40) : "";
}

function sessionIdFromPath(filePath) {
  const match = path.basename(filePath).match(/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i);
  return match ? match[1] : "";
}

function applyStatusUpdate(incoming, source) {
  if (!incoming || typeof incoming !== "object") return false;
  const eventAt = Number(incoming.sent_at) || Date.now();
  const activityChanged = trackActivity(incoming, eventAt);
  const next = {
    ...status,
    ...incoming,
    usage: incoming.usage || status.usage,
    activity: activitySnapshot(),
    source,
  };
  if ((incoming.event === "UserPromptSubmit" || incoming.event === "event_msg:task_started") && !incoming.chat_started_at) {
    next.chat_started_at = eventAt;
  }
  if (next.state !== status.state && !incoming.state_started_at) next.state_started_at = eventAt;
  const changed = next.state !== status.state
    || next.event !== status.event
    || next.tool !== status.tool
    || next.session !== status.session
    || next.project !== status.project
    || next.model !== status.model
    || next.effort !== status.effort
    || next.context?.sampled_at !== status.context?.sampled_at
    || activityChanged;
  status = { ...next, received_at: Date.now() };
  if (changed) broadcast(status);
  return changed;
}

function applyTelemetryUpdate(incoming) {
  if (!incoming || typeof incoming !== "object") return false;
  const next = {
    ...status,
    ...incoming,
    source: status.source,
    received_at: Date.now(),
  };
  const changed = next.model !== status.model
    || next.effort !== status.effort
    || next.context?.sampled_at !== status.context?.sampled_at;
  status = next;
  if (changed) broadcast(status);
  return changed;
}

function schedulePostToolResume(incoming) {
  if (postToolResumeTimer) {
    clearTimeout(postToolResumeTimer);
    postToolResumeTimer = null;
  }
  if (incoming?.event !== "PostToolUse" || incoming?.state === "error") return;
  postToolResumeTimer = setTimeout(() => {
    postToolResumeTimer = null;
    if (status.event !== "PostToolUse" || status.state === "error") return;
    const now = Date.now();
    status = {
      ...status,
      state: "thinking",
      event: "AgentResume",
      tool: "",
      sent_at: now,
      received_at: now,
      state_started_at: now,
      source: "codex-hook",
    };
    broadcast(status);
  }, 700);
  postToolResumeTimer.unref?.();
}

function logKey(record) {
  const payload = record && typeof record.payload === "object" ? record.payload : null;
  return payload && payload.type ? `${record.type}:${payload.type}` : record?.type || "";
}

function normalizeContext(info, sampledAt, history) {
  if (!info || typeof info !== "object") return null;
  const last = info.last_token_usage || info.lastTokenUsage || {};
  const total = info.total_token_usage || info.totalTokenUsage || {};
  const windowTokens = Number(info.model_context_window ?? info.modelContextWindow) || 0;
  const inputTokens = Number(last.input_tokens ?? last.inputTokens) || 0;
  const outputTokens = Number(last.output_tokens ?? last.outputTokens) || 0;
  const reasoningTokens = Number(last.reasoning_output_tokens ?? last.reasoningOutputTokens) || 0;
  const cachedTokens = Number(last.cached_input_tokens ?? last.cachedInputTokens) || 0;
  const usedTokens = Number(last.total_tokens ?? last.totalTokens) || (inputTokens + outputTokens);
  if (!windowTokens || !usedTokens) return null;
  const percent = Math.max(0, Math.min(100, Math.round((usedTokens / windowTokens) * 1000) / 10));
  const point = { percent, used_tokens: usedTokens, at: sampledAt };
  history.push(point);
  if (history.length > 12) history.splice(0, history.length - 12);
  return {
    used_tokens: usedTokens,
    window_tokens: windowTokens,
    remaining_tokens: Math.max(0, windowTokens - usedTokens),
    percent,
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    cached_tokens: cachedTokens,
    reasoning_tokens: reasoningTokens,
    session_total_tokens: Number(total.total_tokens ?? total.totalTokens) || 0,
    sampled_at: sampledAt,
    history: history.slice(),
  };
}

function processLogRecord(record, cursor, emit) {
  if (!record || typeof record !== "object") return;
  const payload = record.payload && typeof record.payload === "object" ? record.payload : {};
  if (record.type === "session_meta") {
    cursor.cwd = typeof payload.cwd === "string" ? payload.cwd : cursor.cwd;
    cursor.session = typeof payload.id === "string" ? payload.id : cursor.session;
    return;
  }
  if (record.type === "turn_context") {
    cursor.cwd = typeof payload.cwd === "string" ? payload.cwd : cursor.cwd;
    cursor.model = typeof payload.model === "string" ? payload.model : cursor.model;
    cursor.effort = typeof payload.effort === "string"
      ? payload.effort
      : (typeof payload.reasoning_effort === "string" ? payload.reasoning_effort : cursor.effort);
    if (emit && (cursor.model !== status.model || cursor.effort !== status.effort)) {
      applyTelemetryUpdate({
        model: cursor.model,
        effort: cursor.effort,
        project: projectFromCwd(cursor.cwd),
      });
    }
    return;
  }
  if (record.type === "event_msg" && payload.type === "token_count") {
    const sampledAt = Date.parse(record.timestamp) || Date.now();
    const context = normalizeContext(payload.info, sampledAt, cursor.contextHistory);
    if (context) cursor.context = context;
    if (emit && context) applyTelemetryUpdate({ context });
    return;
  }

  const key = logKey(record);
  const mapped = LOG_EVENT_STATES[key];
  if (!mapped) return;
  const recordAt = Date.parse(record.timestamp) || Date.now();
  if (key === "event_msg:task_started") {
    cursor.hadToolUse = false;
    cursor.chatStartedAt = recordAt;
  }
  if (key === "response_item:function_call" || key === "response_item:custom_tool_call") cursor.hadToolUse = true;

  let state = mapped;
  if (key === "event_msg:task_complete" && !cursor.hadToolUse) state = "done";
  if (cursor.state !== state || !cursor.stateStartedAt) cursor.stateStartedAt = recordAt;
  cursor.state = state;
  cursor.event = key;
  if (!emit || Date.now() - lastHookAt < 5000) return;

  applyStatusUpdate({
    state,
    event: key,
    project: projectFromCwd(cursor.cwd),
    tool: key.startsWith("response_item:") ? key.slice("response_item:".length) : "",
    session: cursor.session || sessionIdFromPath(cursor.path),
    model: cursor.model || status.model,
    effort: cursor.effort || status.effort,
    sent_at: recordAt,
    chat_elapsed_seconds: cursor.chatStartedAt ? Math.max(0, Math.floor((Date.now() - cursor.chatStartedAt) / 1000)) : 0,
    state_elapsed_seconds: cursor.stateStartedAt ? Math.max(0, Math.floor((Date.now() - cursor.stateStartedAt) / 1000)) : 0,
    chat_started_at: cursor.chatStartedAt || 0,
    state_started_at: cursor.stateStartedAt || 0,
  }, "codex-jsonl");
}

function parseLogText(text, cursor, emit) {
  const combined = (emit ? (cursor.partial || "") : "") + text;
  const lines = combined.split(/\r?\n/);
  const hasTrailingNewline = /\r?\n$/.test(combined);
  cursor.partial = hasTrailingNewline ? "" : (lines.pop() || "");
  if (hasTrailingNewline && lines[lines.length - 1] === "") lines.pop();
  for (const line of lines) {
    if (!line.trim()) continue;
    try { processLogRecord(JSON.parse(line), cursor, emit); } catch { /* tolerate partial JSONL */ }
  }
}

function attachLogFile(file) {
  const cursor = {
    path: file.path,
    offset: file.size,
    partial: "",
    cwd: "",
    session: sessionIdFromPath(file.path),
    model: "",
    effort: "",
    context: null,
    contextHistory: [],
    state: "idle",
    event: "session_meta",
    hadToolUse: false,
    chatStartedAt: 0,
    stateStartedAt: 0,
  };
  parseLogText(readTail(file), cursor, false);
  logCursor = cursor;
  if (cursor.context) applyTelemetryUpdate({ context: cursor.context });
  if (Date.now() - file.mtimeMs < 5 * 60 * 1000 && (cursor.state === "thinking" || cursor.state === "working")) {
    applyStatusUpdate({
      state: cursor.state,
      event: cursor.event,
      project: projectFromCwd(cursor.cwd),
      tool: cursor.event.startsWith("response_item:") ? cursor.event.slice("response_item:".length) : "",
      session: cursor.session,
      model: cursor.model,
      effort: cursor.effort,
      context: cursor.context,
      sent_at: file.mtimeMs,
      chat_elapsed_seconds: cursor.chatStartedAt ? Math.max(0, Math.floor((Date.now() - cursor.chatStartedAt) / 1000)) : 0,
      state_elapsed_seconds: cursor.stateStartedAt ? Math.max(0, Math.floor((Date.now() - cursor.stateStartedAt) / 1000)) : 0,
      chat_started_at: cursor.chatStartedAt || 0,
      state_started_at: cursor.stateStartedAt || 0,
    }, "codex-jsonl-backfill");
  }
}

function pollCodexLog() {
  const latest = newestJsonl(SESSIONS_DIR);
  if (!latest) return;
  if (!logCursor || logCursor.path !== latest.path || latest.size < logCursor.offset) {
    attachLogFile(latest);
    return;
  }
  if (latest.size <= logCursor.offset) return;
  const length = Math.min(latest.size - logCursor.offset, MAX_SESSION_TAIL);
  const start = latest.size - length;
  const buffer = Buffer.alloc(length);
  let fd;
  try {
    fd = fs.openSync(latest.path, "r");
    fs.readSync(fd, buffer, 0, length, start);
  } catch { return; }
  finally { if (fd !== undefined) fs.closeSync(fd); }
  if (start > logCursor.offset) logCursor.partial = "";
  logCursor.offset = latest.size;
  parseLogText(buffer.toString("utf8"), logCursor, true);
}

function newestJsonl(root) {
  let best = null;
  function visit(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        try {
          const stat = fs.statSync(full);
          if (!best || stat.mtimeMs > best.mtimeMs) best = { path: full, mtimeMs: stat.mtimeMs, size: stat.size };
        } catch { /* file may rotate while scanning */ }
      }
    }
  }
  visit(root);
  return best;
}

function recentJsonls(root, limit = 6) {
  const files = [];
  function visit(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        try {
          const stat = fs.statSync(full);
          files.push({ path: full, mtimeMs: stat.mtimeMs, size: stat.size });
        } catch { /* file may rotate while scanning */ }
      }
    }
  }
  visit(root);
  return files.sort((a, b) => b.mtimeMs - a.mtimeMs).slice(0, limit);
}

function readTail(file) {
  const length = Math.min(file.size, MAX_SESSION_TAIL);
  const buffer = Buffer.alloc(length);
  const fd = fs.openSync(file.path, "r");
  try { fs.readSync(fd, buffer, 0, length, file.size - length); }
  finally { fs.closeSync(fd); }
  const text = buffer.toString("utf8");
  return file.size > length ? text.slice(text.indexOf("\n") + 1) : text;
}

function findRateLimits(value) {
  if (!value || typeof value !== "object") return null;
  if (value.rate_limits && typeof value.rate_limits === "object") return value.rate_limits;
  if (value.rateLimits && typeof value.rateLimits === "object") return value.rateLimits;
  for (const child of Object.values(value)) {
    const found = findRateLimits(child);
    if (found) return found;
  }
  return null;
}

function field(value, snake, camel) {
  return value?.[snake] ?? value?.[camel] ?? null;
}

function clockText(epochSeconds) {
  if (!Number.isFinite(Number(epochSeconds))) return "--:--";
  const date = new Date(Number(epochSeconds) * 1000);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
}

function normalizeUsage(limits, sampledAt) {
  if (!limits || typeof limits !== "object") return null;
  const windows = [limits.primary, limits.secondary].filter(Boolean);
  const duration = (item) => Number(field(item, "window_minutes", "windowDurationMins"));
  const fiveHour = windows.find((item) => duration(item) === 300) || limits.primary;
  const weekly = windows.find((item) => duration(item) === 10080) || limits.secondary;
  if (!fiveHour && !weekly) return null;
  const resetAt = field(fiveHour, "resets_at", "resetsAt");
  const rawFivePercent = field(fiveHour, "used_percent", "usedPercent");
  const rawWeeklyPercent = field(weekly, "used_percent", "usedPercent");
  if (rawFivePercent === null || rawWeeklyPercent === null) return null;
  const fivePercent = Number(rawFivePercent);
  const weeklyPercent = Number(rawWeeklyPercent);
  if (!Number.isFinite(fivePercent) || !Number.isFinite(weeklyPercent)) return null;
  return {
    five_hour_percent: fivePercent,
    five_hour_resets_at: Number(resetAt) || 0,
    five_hour_reset_text: clockText(resetAt),
    weekly_percent: weeklyPercent,
    limit_id: String(field(limits, "limit_id", "limitId") || ""),
    limit_name: String(field(limits, "limit_name", "limitName") || ""),
    sampled_at: Number(sampledAt) || Date.now(),
  };
}

function readLocalUsage() {
  const files = recentJsonls(SESSIONS_DIR, 6);
  let fallback = null;
  for (const file of files) {
    const lines = readTail(file).split(/\r?\n/);
    for (let index = lines.length - 1; index >= 0; index -= 1) {
      if (!lines[index].includes("rate_limits") && !lines[index].includes("rateLimits")) continue;
      try {
        const record = JSON.parse(lines[index]);
        const limits = findRateLimits(record);
        const sampledAt = Date.parse(record.timestamp) || file.mtimeMs;
        const usage = normalizeUsage(limits, sampledAt);
        if (!usage) continue;
        if (usage.limit_id === "codex") return usage;
        if (!fallback) fallback = usage;
      } catch { /* skip partial or unrelated JSONL lines */ }
    }
  }
  return fallback;
}

function refreshUsage() {
  const usage = readLocalUsage();
  if (!usage) return false;
  const before = status.usage;
  const changed = !before
    || before.five_hour_percent !== usage.five_hour_percent
    || before.five_hour_resets_at !== usage.five_hour_resets_at
    || before.weekly_percent !== usage.weekly_percent;
  status = { ...status, usage };
  if (changed) broadcast(status);
  return changed;
}

function headers(contentType) {
  return {
    "content-type": contentType,
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}

function json(res, code, value) {
  const body = JSON.stringify(value);
  res.writeHead(code, { ...headers("application/json; charset=utf-8"), "content-length": Buffer.byteLength(body) });
  res.end(body);
}

function sseData(value) {
  const now = Date.now();
  const decorated = {
    ...value,
    chat_elapsed_seconds: value.chat_started_at
      ? Math.max(0, Math.floor((now - value.chat_started_at) / 1000))
      : (value.chat_elapsed_seconds || 0),
    state_elapsed_seconds: value.state_started_at
      ? Math.max(0, Math.floor((now - value.state_started_at) / 1000))
      : (value.state_elapsed_seconds || 0),
  };
  return `data: ${JSON.stringify(decorated)}\n\n`;
}

function broadcast(value) {
  const payload = sseData(value);
  for (const client of clients) {
    try { client.write(payload); } catch { clients.delete(client); }
  }
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY) {
        reject(new Error("body too large"));
        req.destroy();
      } else {
        chunks.push(chunk);
      }
    });
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}")); }
      catch { reject(new Error("invalid json")); }
    });
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
  if (req.method === "OPTIONS") {
    res.writeHead(204, headers("text/plain"));
    res.end();
    return;
  }
  if (req.method === "GET" && url.pathname === "/health") {
    json(res, 200, { ok: true, service: "codex-holocubic", clients: clients.size });
    return;
  }
  if (req.method === "GET" && url.pathname === "/status") {
    json(res, 200, { ok: true, ...status, clients: clients.size });
    return;
  }
  if (req.method === "GET" && url.pathname === "/events") {
    res.writeHead(200, {
      ...headers("text/event-stream; charset=utf-8"),
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    res.write(": clawd connected\n\n");
    res.write(sseData(status));
    clients.add(res);
    req.on("close", () => clients.delete(res));
    return;
  }
  if (req.method === "POST" && url.pathname === "/event") {
    try {
      const incoming = await readJson(req);
      lastHookAt = Date.now();
      if (postToolResumeTimer) {
        clearTimeout(postToolResumeTimer);
        postToolResumeTimer = null;
      }
      applyStatusUpdate(incoming, "codex-hook");
      schedulePostToolResume(incoming);
      json(res, 200, { ok: true, clients: clients.size });
    } catch (error) {
      json(res, error.message === "body too large" ? 413 : 400, { ok: false, error: error.message });
    }
    return;
  }
  json(res, 404, { ok: false, error: "not found" });
});

const heartbeat = setInterval(() => {
  for (const client of clients) {
    try { client.write(": ping\n\n"); } catch { clients.delete(client); }
  }
}, 15000);
heartbeat.unref();

refreshUsage();
const usagePoll = setInterval(refreshUsage, 30000);
usagePoll.unref();
pollCodexLog();
const logPoll = setInterval(pollCodexLog, 1200);
logPoll.unref();

server.listen(PORT, HOST, () => {
  process.stdout.write(`Codex HoloCubic bridge listening on http://${HOST}:${PORT}\n`);
});

function shutdown() {
  clearInterval(heartbeat);
  clearInterval(usagePoll);
  clearInterval(logPoll);
  if (postToolResumeTimer) clearTimeout(postToolResumeTimer);
  for (const client of clients) client.end();
  server.close(() => process.exit(0));
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
