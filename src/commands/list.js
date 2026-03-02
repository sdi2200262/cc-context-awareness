/**
 * List command — display available templates.
 * @module src/commands/list
 */

import fs from 'fs-extra';
import logger from '../ui/logger.js';
import { loadCatalog } from '../core/templates.js';
import { getPaths } from '../core/paths.js';

/** Display available templates from the catalog, marking installed template. */
export async function listCommand() {
  logger.clearAndBanner();

  const catalog = await loadCatalog();

  // Try to read install metadata for installed state
  let activeTemplate = null;
  let activeVersion = null;
  try {
    // Check local first, then global
    for (const global of [false, true]) {
      const paths = getPaths(global);
      if (await fs.pathExists(paths.metaFile)) {
        const meta = await fs.readJson(paths.metaFile);
        activeTemplate = meta.activeTemplate;
        activeVersion = meta.activeTemplateVersion || null;
        break;
      }
    }
  } catch {
    // Ignore errors reading metadata
  }

  logger.info('Available templates:');
  logger.blank();

  for (const t of catalog.templates) {
    let label = logger.chalk.white.bold(t.id);
    if (t.id === activeTemplate) {
      const versionSuffix = activeVersion ? ` v${activeVersion}` : '';
      label += logger.chalk.green(` (installed${versionSuffix})`);
    }
    console.log(`  ${label}`);
    console.log(`  ${logger.chalk.gray(t.description)}`);
    logger.blank();
  }

  logger.dim('Install with: cc-context-awareness install <template>');
}
