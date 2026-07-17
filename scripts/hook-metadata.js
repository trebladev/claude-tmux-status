#!/usr/bin/env node

// Read a Claude hook event and persist only the fields needed to map a tmux
// pane back to Claude's own transcript. Conversation content is not retained.

const fs = require("fs");
const path = require("path");

const [metaPath, updated, claudePid, panePid] = process.argv.slice(2);

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
});
process.stdin.on("end", () => {
  if (!metaPath) return;

  let event;
  try {
    event = JSON.parse(input);
  } catch {
    return;
  }

  const sessionId = stringField(event.session_id, 256);
  const transcriptPath = stringField(event.transcript_path, 8192);
  const cwd = stringField(event.cwd, 8192);
  if (!sessionId || !transcriptPath || !path.isAbsolute(transcriptPath)) return;

  const metadata = {
    sessionId,
    transcriptPath,
    cwd,
    updated: integerField(updated),
    claudePid: integerField(claudePid),
    panePid: integerField(panePid),
  };
  if (!metadata.updated || !metadata.claudePid || !metadata.panePid) return;

  const tempPath = `${metaPath}.${process.pid}`;
  try {
    fs.writeFileSync(tempPath, `${JSON.stringify(metadata)}\n`, {
      encoding: "utf8",
      mode: 0o600,
      flag: "wx",
    });
    fs.renameSync(tempPath, metaPath);
  } catch {
    try {
      fs.unlinkSync(tempPath);
    } catch {}
  }
});

function stringField(value, maxLength) {
  return typeof value === "string" && value.length <= maxLength ? value : "";
}

function integerField(value) {
  return /^\d+$/.test(value || "") ? Number(value) : 0;
}
