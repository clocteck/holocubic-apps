#!/usr/bin/env node
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync, spawn } = require("child_process");

const EVENTS = [
  "SessionStart",
  "UserPromptSubmit",
  "PreToolUse",
  "PermissionRequest",
  "PostToolUse",
  "PreCompact",
  "PostCompact",
  "SubagentStart",
  "SubagentStop",
  "Stop",
];
const MARKER = "codex-holocubic-hook.js";
const SERVER_SCRIPT = "codex-holocubic-server.js";
const STARTUP_VALUE = "CodexHoloCubicBridge";
const STARTUP_KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";

function quotePowerShellLiteral(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function buildStartupCommand(nodePath, serverPath) {
  return `powershell.exe -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -Command "& ${quotePowerShellLiteral(nodePath)} ${quotePowerShellLiteral(serverPath)}"`;
}

function startBridgeDetached() {
  try {
    const child = spawn(process.execPath, [path.resolve(__dirname, SERVER_SCRIPT)], {
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

function installStartup() {
  if (process.platform !== "win32") return false;
  const command = buildStartupCommand(process.execPath, path.resolve(__dirname, SERVER_SCRIPT));
  execFileSync("reg.exe", ["add", STARTUP_KEY, "/v", STARTUP_VALUE, "/t", "REG_SZ", "/d", command, "/f"], {
    windowsHide: true,
    stdio: "ignore",
  });
  return true;
}

function uninstallStartup() {
  if (process.platform !== "win32") return false;
  try {
    execFileSync("reg.exe", ["delete", STARTUP_KEY, "/v", STARTUP_VALUE, "/f"], {
      windowsHide: true,
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

function atomicWrite(filePath, contents) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.tmp-${process.pid}`;
  fs.writeFileSync(temporary, contents, "utf8");
  fs.renameSync(temporary, filePath);
}

function backupOnce(filePath) {
  if (!fs.existsSync(filePath)) return;
  const backup = `${filePath}.holo-pet.bak`;
  if (!fs.existsSync(backup)) fs.copyFileSync(filePath, backup);
}

function toWslPath(value) {
  const match = /^([A-Za-z]):[\\/](.*)$/.exec(value);
  if (!match) return value.replace(/\\/g, "/");
  return `/mnt/${match[1].toLowerCase()}/${match[2].replace(/\\/g, "/")}`;
}

function commandContainsMarker(value) {
  return typeof value === "string" && value.includes(MARKER);
}

function entryContainsMarker(entry) {
  if (!entry || typeof entry !== "object") return false;
  if (commandContainsMarker(entry.command) || commandContainsMarker(entry.commandWindows)) return true;
  return Array.isArray(entry.hooks) && entry.hooks.some(entryContainsMarker);
}

function ensureFeatureEnabled(configPath) {
  const original = fs.existsSync(configPath) ? fs.readFileSync(configPath, "utf8") : "";
  const newline = original.includes("\r\n") ? "\r\n" : "\n";
  const lines = original ? original.split(/\r?\n/) : [];
  let start = -1;
  let end = lines.length;

  for (let i = 0; i < lines.length; i += 1) {
    if (/^\s*\[features\]\s*$/.test(lines[i])) {
      start = i;
      continue;
    }
    if (start >= 0 && i > start && /^\s*\[/.test(lines[i])) {
      end = i;
      break;
    }
  }

  if (start < 0) {
    if (lines.length && lines[lines.length - 1] !== "") lines.push("");
    lines.push("[features]", "hooks = true");
  } else {
    let replaced = false;
    for (let i = start + 1; i < end; i += 1) {
      if (/^\s*hooks\s*=/.test(lines[i])) {
        lines[i] = "hooks = true";
        replaced = true;
        break;
      }
    }
    if (!replaced) lines.splice(start + 1, 0, "hooks = true");
  }

  const next = `${lines.join(newline).replace(/\s*$/, "")}${newline}`;
  if (next !== original) {
    backupOnce(configPath);
    atomicWrite(configPath, next);
  }
}

function install(codexHome) {
  const hooksPath = path.join(codexHome, "hooks.json");
  const configPath = path.join(codexHome, "config.toml");
  const scriptPath = path.resolve(__dirname, MARKER);
  const commandWindows = `& "${process.execPath}" "${scriptPath}"`;
  const command = `node "${toWslPath(scriptPath)}"`;
  const settings = fs.existsSync(hooksPath)
    ? JSON.parse(fs.readFileSync(hooksPath, "utf8"))
    : {};
  if (!settings.hooks || typeof settings.hooks !== "object") settings.hooks = {};

  let added = 0;
  for (const event of EVENTS) {
    if (!Array.isArray(settings.hooks[event])) settings.hooks[event] = [];
    if (settings.hooks[event].some(entryContainsMarker)) continue;
    settings.hooks[event].push({
      hooks: [{ type: "command", command, commandWindows, timeout: 5 }],
    });
    added += 1;
  }

  if (added > 0) {
    backupOnce(hooksPath);
    atomicWrite(hooksPath, `${JSON.stringify(settings, null, 2)}\n`);
  }
  ensureFeatureEnabled(configPath);
  let startupInstalled = false;
  try { startupInstalled = installStartup(); } catch { startupInstalled = false; }
  const bridgeStarted = startBridgeDetached();
  return { added, hooksPath, configPath, startupInstalled, bridgeStarted };
}

function uninstall(codexHome) {
  const hooksPath = path.join(codexHome, "hooks.json");
  if (!fs.existsSync(hooksPath)) return { removed: 0, hooksPath, startupRemoved: uninstallStartup() };
  const settings = JSON.parse(fs.readFileSync(hooksPath, "utf8"));
  if (!settings.hooks || typeof settings.hooks !== "object") {
    return { removed: 0, hooksPath, startupRemoved: uninstallStartup() };
  }
  let removed = 0;
  for (const [event, entries] of Object.entries(settings.hooks)) {
    if (!Array.isArray(entries)) continue;
    const kept = entries.filter((entry) => {
      if (!entryContainsMarker(entry)) return true;
      removed += 1;
      return false;
    });
    if (kept.length) settings.hooks[event] = kept;
    else delete settings.hooks[event];
  }
  if (removed > 0) {
    backupOnce(hooksPath);
    atomicWrite(hooksPath, `${JSON.stringify(settings, null, 2)}\n`);
  }
  return { removed, hooksPath, startupRemoved: uninstallStartup() };
}

if (require.main === module) {
  const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
  const result = process.argv.includes("--uninstall") ? uninstall(codexHome) : install(codexHome);
  console.log(JSON.stringify(result, null, 2));
  if (!process.argv.includes("--uninstall") && result.added > 0) {
    console.log("Review the new command hook in Codex /hooks if prompted.");
  }
}

module.exports = {
  EVENTS,
  MARKER,
  buildStartupCommand,
  ensureFeatureEnabled,
  install,
  installStartup,
  startBridgeDetached,
  uninstall,
  uninstallStartup,
};
