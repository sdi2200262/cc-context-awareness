/**
 * Status command — show what's installed.
 * @module src/commands/status
 */

import fs from 'fs-extra';
import logger from '../ui/logger.js';
import { getPaths } from '../core/paths.js';
import { readConfig } from '../core/config.js';

/**
 * Show current installation status, config, and active template.
 * @param {Object} [options]
 * @param {boolean} [options.global] - Check global (~/.claude/) install.
 */
export async function statusCommand(options = {}) {
  const isGlobal = !!options.global;
  const paths = getPaths(isGlobal);
  const scope = isGlobal ? 'global' : 'local';

  logger.clearAndBanner();

  if (!await fs.pathExists(paths.metaFile)) {
    logger.warn(`cc-context-awareness is not installed (${scope}).`);
    logger.dim('Run: npx cc-context-awareness', { indent: true });
    return;
  }

  const meta = await fs.readJson(paths.metaFile);
  const config = await readConfig(paths.configFile);
  const thresholdCount = config?.thresholds?.length || 0;

  logger.info(`Install scope: ${scope}`);
  logger.info(`Version: ${meta.version || 'unknown'}`);
  logger.info(`Config: ${paths.configFile}`);
  logger.info(`Settings: ${paths.settingsFile}`);
  logger.info(`Thresholds: ${thresholdCount}`);

  if (config?.thresholds) {
    for (const t of config.thresholds) {
      logger.dim(`  ${t.percent}% — ${t.level}`, { indent: true });
    }
  }

  logger.blank();

  if (meta.activeTemplate) {
    logger.info(`Active template: ${logger.chalk.white.bold(meta.activeTemplate)}`);
  } else {
    logger.info('Active template: none');
  }
}
