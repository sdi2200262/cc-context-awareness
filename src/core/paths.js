/**
 * Path resolution for install targets and package resources.
 * @module src/core/paths
 */

import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(__dirname, '..', '..');

/**
 * Resolves all installation paths based on scope.
 * @param {boolean} global - Use ~/.claude/ (true) or ./.claude/ (false)
 * @returns {{ claudeDir: string, installDir: string, settingsFile: string, configFile: string, skillDir: string, metaFile: string }}
 */
export function getPaths(global) {
  const claudeDir = global
    ? path.join(process.env.HOME, '.claude')
    : path.join(process.cwd(), '.claude');

  const installDir = path.join(claudeDir, 'cc-context-awareness');
  const settingsFile = global
    ? path.join(claudeDir, 'settings.json')
    : path.join(claudeDir, 'settings.local.json');
  const configFile = path.join(installDir, 'config.json');
  const skillDir = path.join(claudeDir, 'skills', 'configure-context-awareness');
  const metaFile = path.join(installDir, '.install-meta.json');

  return { claudeDir, installDir, settingsFile, configFile, skillDir, metaFile };
}

/**
 * Resolves runtime/ directory within the npm package.
 * @returns {string}
 */
export function getRuntimeDir() {
  return path.join(PKG_ROOT, 'runtime');
}

/**
 * Resolves templates/ directory within the npm package.
 * @returns {string}
 */
export function getTemplatesDir() {
  return path.join(PKG_ROOT, 'templates');
}

/**
 * Resolves docs/ directory within the npm package.
 * @returns {string}
 */
export function getDocsDir() {
  return path.join(PKG_ROOT, 'docs');
}
