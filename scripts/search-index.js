#!/usr/bin/env node

// Emit tab-separated fzf candidates for all tmux windows and for chat messages
// belonging to Claude sessions currently mapped to a live tmux pane.

const fs = require("fs");
const os = require("os");
const path = require("path");
const { execFileSync } = require("child_process");

const stateDir =
  process.env.CLAUDE_TMUX_STATUS_DIR ||
  path.join(os.tmpdir(), `claude-tmux-status-${process.getuid()}`);
const configRoot = path.resolve(
  process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude"),
);
const projectsRoot = path.join(configRoot, "projects");

const paneFormat = [
  "#{session_id}",
  "#{session_name}",
  "#{window_id}",
  "#{window_index}",
  "#{window_name}",
  "#{pane_id}",
  "#{pane_index}",
  "#{pane_active}",
  "#{pane_pid}",
  "#{pane_current_path}",
].join("\t");

let paneOutput = "";
try {
  paneOutput = execFileSync("tmux", ["list-panes", "-a", "-F", paneFormat], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
} catch {
  process.exit(0);
}

const panes = paneOutput
  .split("\n")
  .filter(Boolean)
  .map(parsePane)
  .filter(Boolean);

const stateDirIsPrivate = privateStateDir(stateDir);
const windowStates = new Map();
if (stateDirIsPrivate) {
  for (const pane of panes) {
    const state = readPaneState(pane);
    if (!state || state === "stopped") continue;
    const current = windowStates.get(pane.windowId);
    if (!current || statePriority(state) > statePriority(current)) {
      windowStates.set(pane.windowId, state);
    }
  }
}

const windows = new Map();
for (const pane of panes) {
  const current = windows.get(pane.windowId);
  if (!current || pane.active) windows.set(pane.windowId, pane);
}

for (const pane of windows.values()) {
  const location = `${pane.sessionName}:${pane.windowIndex}`;
  const status = statusLabel(windowStates.get(pane.windowId));
  emit([
    "window",
    pane.sessionId,
    pane.windowId,
    pane.paneId,
    "",
    `󰖯  ${location}  ${pane.windowName}  ${pane.cwd}${status}`,
  ]);
}

if (!stateDirIsPrivate) process.exit(0);

for (const pane of panes) {
  const metadata = readMetadata(pane);
  if (!metadata) continue;
  const messages = readTranscript(metadata.transcriptPath);
  const location = `${pane.sessionName}:${pane.windowIndex}.${pane.paneIndex}`;
  for (const message of messages) {
    const roleIcon = message.role === "user" ? "󰭹" : "󰚩";
    const title = message.title ? `  ${message.title}` : "";
    emit([
      "chat",
      pane.sessionId,
      pane.windowId,
      pane.paneId,
      Buffer.from(message.preview, "utf8").toString("base64"),
      `${roleIcon}  ${location}${title}  ${message.search}`,
    ]);
  }
}

function parsePane(line) {
  const fields = line.split("\t");
  if (fields.length < 10) return null;
  return {
    sessionId: fields[0],
    sessionName: clean(fields[1]),
    windowId: fields[2],
    windowIndex: fields[3],
    windowName: clean(fields[4]),
    paneId: fields[5],
    paneIndex: fields[6],
    active: fields[7] === "1",
    panePid: Number(fields[8]),
    cwd: clean(fields.slice(9).join("\t")),
  };
}

function privateStateDir(dir) {
  try {
    const stat = fs.statSync(dir);
    return stat.isDirectory() && stat.uid === process.getuid();
  } catch {
    return false;
  }
}

function readStateFields(pane) {
  const paneKey = pane.paneId.replace(/^%/, "");
  const statePath = path.join(stateDir, `pane-${paneKey}`);
  try {
    const fields = fs.readFileSync(statePath, "utf8").trimEnd().split("\t");
    if (Number(fields[3]) !== pane.panePid) return null;
    return fields;
  } catch {
    return null;
  }
}

function readPaneState(pane) {
  const fields = readStateFields(pane);
  if (!fields) return null;
  let state = fields[0];
  if (!["working", "waiting", "error", "stopped"].includes(state)) return null;
  if (state !== "stopped" && !processIsAlive(Number(fields[2]))) {
    state = "stopped";
  }
  return state;
}

function processIsAlive(pid) {
  if (!Number.isSafeInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error && error.code === "EPERM";
  }
}

function statePriority(state) {
  return { working: 2, waiting: 3, error: 4 }[state] || 0;
}

function statusLabel(state) {
  const colours = {
    working: "#a6d189",
    waiting: "#e5c890",
    error: "#e78284",
  };
  const colour = colours[state];
  return colour
    ? `  \u001b[38;2;${hexRgb(colour)}m● Claude: ${state}\u001b[0m`
    : "";
}

function hexRgb(colour) {
  const value = colour.slice(1);
  return [0, 2, 4]
    .map((offset) => Number.parseInt(value.slice(offset, offset + 2), 16))
    .join(";");
}

function readMetadata(pane) {
  const paneKey = pane.paneId.replace(/^%/, "");
  const statePath = path.join(stateDir, `pane-${paneKey}`);
  const metaPath = `${statePath}.meta`;
  try {
    const state = readStateFields(pane);
    if (!state) return null;
    if (Number(state[3]) !== pane.panePid) return null;
    const metadata = JSON.parse(fs.readFileSync(metaPath, "utf8"));
    if (metadata.panePid !== pane.panePid) return null;
    const transcriptPath = resolveTranscript(metadata.transcriptPath);
    if (!transcriptPath) return null;
    return { ...metadata, transcriptPath };
  } catch {
    return null;
  }
}

function resolveTranscript(value) {
  if (typeof value !== "string") return null;
  const expanded = value.startsWith("~/")
    ? path.join(os.homedir(), value.slice(2))
    : value;
  const resolved = path.resolve(expanded);
  if (
    resolved !== projectsRoot &&
    !resolved.startsWith(`${projectsRoot}${path.sep}`)
  ) {
    return null;
  }
  return resolved.endsWith(".jsonl") ? resolved : null;
}

function readTranscript(transcriptPath) {
  let lines;
  try {
    lines = fs.readFileSync(transcriptPath, "utf8").split("\n");
  } catch {
    return [];
  }

  let title = "";
  const messages = [];
  for (const line of lines) {
    if (!line) continue;
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    if (entry.type === "ai-title" && typeof entry.aiTitle === "string") {
      title = clean(entry.aiTitle);
      continue;
    }
    if (entry.isSidechain === true) continue;
    const role =
      entry.type === "user"
        ? "user"
        : entry.type === "assistant"
          ? "assistant"
          : null;
    if (!role || entry.isMeta) continue;
    const text = messageText(entry.message && entry.message.content);
    if (!text) continue;
    messages.push({
      role,
      title,
      search: clean(text),
      preview: `${role === "user" ? "You" : "Claude"}\n\n${safePreview(text)}`,
    });
  }
  return messages.reverse();
}

function messageText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter(
      (part) =>
        part && part.type === "text" && typeof part.text === "string",
    )
    .map((part) => part.text)
    .join("\n");
}

function clean(value) {
  return String(value || "")
    .replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function safePreview(value) {
  return String(value || "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .slice(0, 100000);
}

function emit(fields) {
  process.stdout.write(`${fields.map(cleanField).join("\t")}\n`);
}

function cleanField(value) {
  return String(value || "").replace(/[\t\r\n\u0000]/g, " ");
}
