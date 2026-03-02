/**
 * Remove command — remove a template's assets.
 * @module src/commands/remove
 */

import fs from 'fs-extra';
import path from 'path';
import logger from '../ui/logger.js';
import { getPaths } from '../core/paths.js';
import { removeThresholdsByPrefix } from '../core/config.js';
import { readSettings, writeSettings, removeHook, removePermissions } from '../core/settings.js';
import { loadLocalManifest } from '../core/templates.js';
import { CLIError } from '../core/errors.js';

/**
 * Remove a template by id.
 * @param {string} templateId
 * @param {Object} options
 */
export async function removeCommand(templateId, options = {}) {
  const isGlobal = !!options.global;
  const paths = getPaths(isGlobal);
  const scope = isGlobal ? 'global' : 'local';

  if (!await fs.pathExists(paths.metaFile)) {
    throw CLIError.baseNotInstalled();
  }

  const meta = await fs.readJson(paths.metaFile);

  if (meta.activeTemplate !== templateId) {
    logger.warn(`Template "${templateId}" is not currently active.`);
    if (meta.activeTemplate) {
      logger.dim(`Active template: ${meta.activeTemplate}`, { indent: true });
    } else {
      logger.dim('No template is currently active.', { indent: true });
    }
    return;
  }

  logger.clearAndBanner();
  logger.info(`Removing template: ${templateId} (${scope})...`);

  await removeTemplateAssets(templateId, paths);

  // Update metadata
  meta.activeTemplate = null;
  meta.activeTemplateVersion = null;
  await fs.writeJson(paths.metaFile, meta, { spaces: 2 });

  logger.blank();
  logger.success(`${templateId} removed.`);
  logger.dim('Restart Claude Code to apply changes.', { indent: true });
}

/**
 * Remove all assets for a template. Used by both remove and install (when switching).
 * Reads manifest from local install dir (saved during install), falls back to best-effort.
 * @param {string} templateId
 * @param {Object} paths
 */
export async function removeTemplateAssets(templateId, paths) {
  const templateInstallDir = path.join(paths.claudeDir, templateId);

  // Try to load the locally saved manifest
  let manifest = await loadLocalManifest(templateInstallDir);
  if (!manifest) {
    // Best-effort cleanup if manifest not found (v1.0.0 → v1.1.0 migration)
    logger.warn(`Could not load manifest for ${templateId}, doing best-effort cleanup`);
    if (await fs.pathExists(templateInstallDir)) {
      await fs.remove(templateInstallDir);
    }
    return;
  }

  const settings = await readSettings(paths.settingsFile);

  // 1. Remove thresholds
  if (manifest.thresholds_level_prefix) {
    const removed = await removeThresholdsByPrefix(paths.configFile, manifest.thresholds_level_prefix);
    if (removed > 0) {
      logger.info(`Removed ${removed} thresholds`);
    }
  }

  // 2. Remove hooks from settings
  if (manifest.hooks && manifest.hooks.length > 0) {
    for (const hook of manifest.hooks) {
      const hookPath = path.join(templateInstallDir, hook.script);
      removeHook(settings, hookPath);
    }
    logger.info('Removed hooks from settings');
  }

  // 3. Remove permissions
  if (manifest.permissions && manifest.permissions.length > 0) {
    const removed = removePermissions(settings, manifest.permissions);
    if (removed > 0) {
      logger.info(`Removed ${removed} permission patterns`);
    }
  }

  // 4. Remove agents
  if (manifest.agents && manifest.agents.length > 0) {
    for (const agent of manifest.agents) {
      const agentPath = path.join(paths.claudeDir, agent.dest);
      if (await fs.pathExists(agentPath)) {
        await fs.remove(agentPath);
        logger.info(`Removed ${path.basename(agent.dest)}`);
      }
    }
    // Clean up empty agents dir
    const agentsDir = path.join(paths.claudeDir, 'agents');
    if (await fs.pathExists(agentsDir)) {
      const items = await fs.readdir(agentsDir);
      if (items.length === 0) await fs.remove(agentsDir);
    }
  }

  // 5. Write updated settings
  await writeSettings(paths.settingsFile, settings);

  // 6. Remove template install directory
  if (await fs.pathExists(templateInstallDir)) {
    await fs.remove(templateInstallDir);
  }
}
