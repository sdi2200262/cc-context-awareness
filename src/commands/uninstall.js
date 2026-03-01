/**
 * Uninstall command — remove everything.
 * @module src/commands/uninstall
 */

import fs from 'fs-extra';
import path from 'path';
import { execSync } from 'child_process';
import logger from '../ui/logger.js';
import { confirmAction } from '../ui/prompts.js';
import { getPaths } from '../core/paths.js';
import { readSettings, writeSettings, removeStatusLine, removeHook } from '../core/settings.js';
import { removeTemplateAssets } from './remove.js';

/**
 * Remove cc-context-awareness, all templates, hooks, and settings entries.
 * @param {Object} [options]
 * @param {boolean} [options.global] - Target global (~/.claude/) install.
 */
export async function uninstallCommand(options = {}) {
  const isGlobal = !!options.global;
  const paths = getPaths(isGlobal);
  const scope = isGlobal ? 'global' : 'local';

  logger.clearAndBanner();

  if (!await fs.pathExists(paths.installDir)) {
    logger.warn(`cc-context-awareness is not installed (${scope}).`);
    return;
  }

  logger.warn('This will remove cc-context-awareness and all templates.');
  const confirmed = await confirmAction('Are you sure?', false);
  if (!confirmed) {
    logger.info('Cancelled.');
    return;
  }

  logger.clearAndBanner();
  logger.info(`Uninstalling cc-context-awareness (${scope})...`);

  // Remove active template first
  if (await fs.pathExists(paths.metaFile)) {
    const meta = await fs.readJson(paths.metaFile);
    if (meta.activeTemplate) {
      logger.info(`Removing template: ${meta.activeTemplate}...`);
      await removeTemplateAssets(meta.activeTemplate, paths);
      logger.success(`Removed ${meta.activeTemplate}`);
    }
  }

  // Clean up settings
  const settings = await readSettings(paths.settingsFile);
  const bridgePath = path.join(paths.installDir, 'bridge.sh');
  const checkPath = path.join(paths.installDir, 'check-thresholds.sh');
  const resetPath = path.join(paths.installDir, 'reset.sh');

  removeStatusLine(settings, bridgePath);
  removeHook(settings, checkPath);
  removeHook(settings, resetPath);

  const result = await writeSettings(paths.settingsFile, settings);
  if (result === 'removed') {
    logger.success(`Removed empty ${path.basename(paths.settingsFile)}`);
  } else {
    logger.success(`Updated ${path.basename(paths.settingsFile)}`);
  }

  // Remove install directory
  await fs.remove(paths.installDir);
  logger.success(`Removed ${paths.installDir}`);

  // Remove skill directory
  if (await fs.pathExists(paths.skillDir)) {
    await fs.remove(paths.skillDir);
    logger.info('Removed agent skill');

    // Clean up empty skills directory
    const skillsParent = path.dirname(paths.skillDir);
    if (await fs.pathExists(skillsParent)) {
      const items = await fs.readdir(skillsParent);
      if (items.length === 0) await fs.remove(skillsParent);
    }
  }

  // Clean up flag files
  try {
    execSync('rm -f /tmp/.cc-ctx-pct-* /tmp/.cc-ctx-fired-* /tmp/.cc-ctx-compacted-*', { stdio: 'ignore' });
    logger.info('Cleaned up flag files');
  } catch {
    // Ignore errors
  }

  logger.blank();
  logger.success(`cc-context-awareness uninstalled (${scope}).`);
  logger.dim('Restart Claude Code to apply changes.', { indent: true });
}
