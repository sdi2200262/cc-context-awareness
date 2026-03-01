/**
 * Settings.json statusLine + hook management.
 * Pure logic — no UI dependencies.
 * @module src/core/settings
 */

import fs from 'fs-extra';
import path from 'path';
import { CLIError } from './errors.js';

/**
 * Read settings.json. Returns empty object if file doesn't exist.
 * @param {string} settingsPath
 * @returns {Promise<Object>}
 */
export async function readSettings(settingsPath) {
  try {
    if (!await fs.pathExists(settingsPath)) return {};
    const raw = await fs.readFile(settingsPath, 'utf-8');
    return JSON.parse(raw);
  } catch {
    throw CLIError.settingsCorrupted(settingsPath);
  }
}

/**
 * Write settings.json with pretty formatting.
 * Removes empty file if settings object is empty.
 * @param {string} settingsPath
 * @param {Object} settings
 * @returns {Promise<'written'|'removed'>}
 */
export async function writeSettings(settingsPath, settings) {
  // If settings is now empty, remove the file
  if (Object.keys(settings).length === 0) {
    await fs.remove(settingsPath);
    return 'removed';
  }
  await fs.ensureDir(path.dirname(settingsPath));
  await fs.writeFile(settingsPath, JSON.stringify(settings, null, 2) + '\n');
  return 'written';
}

/**
 * Set the statusLine in settings. Handles three cases:
 * 1. No existing statusLine → set bridge as sole command
 * 2. Already has bridge → skip (idempotent)
 * 3. Has other command → prepend bridge as pipe: "bridge.sh | existing"
 * @param {Object} settings
 * @param {string} bridgePath - Absolute path to bridge.sh
 * @returns {{ action: 'created'|'prepended'|'already_present', command: string, settings: Object }}
 */
export function setStatusLine(settings, bridgePath) {
  const bridgeCmd = bridgePath;

  if (!settings.statusLine) {
    settings.statusLine = bridgeCmd;
    return { action: 'created', command: bridgeCmd, settings };
  }

  // Extract the existing command string
  const existing = typeof settings.statusLine === 'string'
    ? settings.statusLine
    : settings.statusLine.command || '';

  // Already has bridge
  if (existing.includes(bridgePath)) {
    return { action: 'already_present', command: existing, settings };
  }

  // Prepend bridge as pipe
  const piped = `${bridgePath} | ${existing}`;
  settings.statusLine = piped;
  return { action: 'prepended', command: piped, settings };
}

/**
 * Remove bridge from statusLine. Handles:
 * 1. Just bridge → delete statusLine key
 * 2. Piped "bridge | downstream" → restore downstream
 * 3. No bridge present → no-op
 * @param {Object} settings
 * @param {string} bridgePath
 * @returns {{ action: 'removed'|'restored'|'not_present', settings: Object }}
 */
export function removeStatusLine(settings, bridgePath) {
  if (!settings.statusLine) {
    return { action: 'not_present', settings };
  }

  const existing = typeof settings.statusLine === 'string'
    ? settings.statusLine
    : settings.statusLine.command || '';

  if (!existing.includes(bridgePath)) {
    return { action: 'not_present', settings };
  }

  // Check if bridge is the only command
  const trimmed = existing.replace(bridgePath, '').trim();
  if (!trimmed || trimmed === '|') {
    delete settings.statusLine;
    return { action: 'removed', settings };
  }

  // Restore downstream (remove "bridge.sh | " prefix)
  const downstream = trimmed.replace(/^\|\s*/, '').replace(/\s*\|\s*$/, '');
  if (downstream) {
    settings.statusLine = downstream;
    return { action: 'restored', settings };
  }

  delete settings.statusLine;
  return { action: 'removed', settings };
}

/**
 * Add a hook entry. Returns false if duplicate (by command path).
 * @param {Object} settings
 * @param {string} event - Hook event name (e.g. "PreToolUse", "SessionStart")
 * @param {string} matcher - Hook matcher string
 * @param {string} commandPath - Absolute path to hook script
 * @returns {boolean} true if added, false if duplicate
 */
export function addHook(settings, event, matcher, commandPath) {
  if (!settings.hooks) settings.hooks = {};
  if (!settings.hooks[event]) settings.hooks[event] = [];

  // Check for duplicate
  const isDuplicate = settings.hooks[event].some(entry =>
    entry.hooks && entry.hooks.some(h => h.command === commandPath)
  );
  if (isDuplicate) return false;

  settings.hooks[event].push({
    matcher,
    hooks: [{ type: 'command', command: commandPath }],
  });

  return true;
}

/**
 * Remove a hook by command path. Cleans empty event arrays and hooks object.
 * @param {Object} settings
 * @param {string} commandPath
 * @returns {boolean} true if removed, false if not found
 */
export function removeHook(settings, commandPath) {
  if (!settings.hooks) return false;

  let found = false;

  for (const event of Object.keys(settings.hooks)) {
    const before = settings.hooks[event].length;
    settings.hooks[event] = settings.hooks[event].filter(entry =>
      !entry.hooks || !entry.hooks.some(h => h.command === commandPath)
    );

    if (settings.hooks[event].length < before) found = true;

    // Clean empty arrays
    if (settings.hooks[event].length === 0) {
      delete settings.hooks[event];
    }
  }

  // Clean empty hooks object
  if (Object.keys(settings.hooks).length === 0) {
    delete settings.hooks;
  }

  return found;
}
