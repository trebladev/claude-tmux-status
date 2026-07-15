#!/usr/bin/env node

const fs = require("fs");
const os = require("os");
const path = require("path");

const MARKER = "claude-tmux-status-v1";
const action = process.argv[2];
const hookScript = process.argv[3] ? path.resolve(process.argv[3]) : null;

if (!['install', 'uninstall'].includes(action)) {
  console.error('usage: configure-hooks.js <install|uninstall> [hook-script]');
  process.exit(2);
}
if (action === 'install' && !hookScript) {
  console.error('install requires the hook script path');
  process.exit(2);
}

const configRoot = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const settingsPath = path.join(configRoot, 'settings.json');

let settings = {};
let original = '';
if (fs.existsSync(settingsPath)) {
  original = fs.readFileSync(settingsPath, 'utf8');
  try {
    settings = JSON.parse(original);
  } catch (error) {
    console.error(`claude-tmux-status: ${settingsPath} is not valid JSON: ${error.message}`);
    process.exit(1);
  }
}

if (!settings || Array.isArray(settings) || typeof settings !== 'object') {
  console.error(`claude-tmux-status: ${settingsPath} must contain a JSON object`);
  process.exit(1);
}

settings.hooks = settings.hooks &&
  !Array.isArray(settings.hooks) &&
  typeof settings.hooks === 'object'
  ? settings.hooks
  : {};

function isOurs(handler) {
  return handler &&
    handler.type === 'command' &&
    Array.isArray(handler.args) &&
    handler.args.includes(MARKER);
}

// Remove entries from older locations first, making install and uninstall
// idempotent without touching any unrelated user hooks.
for (const [event, groups] of Object.entries(settings.hooks)) {
  if (!Array.isArray(groups)) continue;
  const cleaned = groups
    .map((group) => {
      if (!group || !Array.isArray(group.hooks)) return group;
      return { ...group, hooks: group.hooks.filter((handler) => !isOurs(handler)) };
    })
    .filter((group) => !group || !Array.isArray(group.hooks) || group.hooks.length > 0);

  if (cleaned.length > 0) settings.hooks[event] = cleaned;
  else delete settings.hooks[event];
}

function addHook(event, state, matcher) {
  const handler = {
    type: 'command',
    command: hookScript,
    args: [state, MARKER],
    timeout: 5,
  };
  const group = { hooks: [handler] };
  if (matcher) group.matcher = matcher;
  if (!Array.isArray(settings.hooks[event])) settings.hooks[event] = [];
  settings.hooks[event].push(group);
}

if (action === 'install') {
  addHook('SessionStart', 'waiting');
  addHook('UserPromptSubmit', 'working');
  addHook('PreToolUse', 'working', '*');
  addHook('PermissionRequest', 'waiting', '*');
  addHook('Notification', 'waiting', 'permission_prompt|idle_prompt|elicitation_dialog');
  addHook('Stop', 'waiting');
  addHook('StopFailure', 'error', '*');
  addHook('SessionEnd', 'stopped');
}

if (Object.keys(settings.hooks).length === 0) delete settings.hooks;

const next = `${JSON.stringify(settings, null, 2)}\n`;
if (next === original) process.exit(0);

fs.mkdirSync(configRoot, { recursive: true, mode: 0o700 });
if (original) {
  const backupPath = `${settingsPath}.claude-tmux-status.bak`;
  if (!fs.existsSync(backupPath)) fs.copyFileSync(settingsPath, backupPath);
}

const tempPath = `${settingsPath}.tmp-${process.pid}`;
fs.writeFileSync(tempPath, next, { mode: 0o600 });
fs.renameSync(tempPath, settingsPath);
