/**
 * Config.json read/write/upsert/remove operations.
 * Pure logic — no UI dependencies.
 * @module src/core/config
 */

import fs from 'fs-extra';
import path from 'path';
import { CLIError } from './errors.js';
import { getRuntimeDir } from './paths.js';

/**
 * Read and parse config.json.
 * @param {string} configPath
 * @returns {Promise<Object>}
 */
export async function readConfig(configPath) {
  try {
    return await fs.readJson(configPath);
  } catch (err) {
    if (err.code === 'ENOENT') return null;
    throw CLIError.configCorrupted(configPath);
  }
}

/**
 * Write config.json with pretty formatting.
 * @param {string} configPath
 * @param {Object} config
 * @returns {Promise<void>}
 */
export async function writeConfig(configPath, config) {
  await fs.ensureDir(path.dirname(configPath));
  await fs.writeJson(configPath, config, { spaces: 2 });
}

/**
 * Create default config.json from runtime/config.default.json.
 * @param {string} configPath
 * @returns {Promise<Object>} The created config.
 */
export async function createDefaultConfig(configPath) {
  const defaultPath = path.join(getRuntimeDir(), 'config.default.json');
  const config = await fs.readJson(defaultPath);
  await writeConfig(configPath, config);
  return config;
}

/**
 * Upsert thresholds from a template's thresholds file.
 * Prepends new thresholds, replaces existing ones with matching levels.
 * @param {string} configPath
 * @param {Array} newThresholds
 * @returns {Promise<{added: number, updated: number}>}
 */
export async function upsertThresholds(configPath, newThresholds) {
  const config = await readConfig(configPath);
  if (!config) throw CLIError.configCorrupted(configPath);

  const existing = config.thresholds || [];
  const newLevels = new Set(newThresholds.map(t => t.level));

  // Keep existing thresholds that don't conflict with new ones
  const kept = existing.filter(t => !newLevels.has(t.level));

  // Count how many were replaced vs added
  const updated = existing.length - kept.length;
  const added = newThresholds.length - updated;

  config.thresholds = [...newThresholds, ...kept];
  await writeConfig(configPath, config);

  return { added, updated };
}

/**
 * Remove thresholds matching a level prefix.
 * @param {string} configPath
 * @param {string} prefix - e.g. "memory-" removes memory-50, memory-65, memory-80.
 * @returns {Promise<number>} Number of thresholds removed.
 */
export async function removeThresholdsByPrefix(configPath, prefix) {
  const config = await readConfig(configPath);
  if (!config) return 0;

  const before = (config.thresholds || []).length;
  config.thresholds = (config.thresholds || []).filter(
    t => !t.level.startsWith(prefix)
  );
  const removed = before - config.thresholds.length;

  if (removed > 0) {
    await writeConfig(configPath, config);
  }

  return removed;
}
