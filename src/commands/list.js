/**
 * List command — display available templates.
 * @module src/commands/list
 */

import logger from '../ui/logger.js';
import { loadCatalog } from '../core/templates.js';

/** Display available templates from the catalog. */
export async function listCommand() {
  logger.clearAndBanner();

  const catalog = await loadCatalog();

  logger.info('Available templates:');
  logger.blank();

  for (const t of catalog.templates) {
    console.log(`  ${logger.chalk.white.bold(t.id)}`);
    console.log(`  ${logger.chalk.gray(t.description)}`);
    logger.blank();
  }

  logger.dim('Install with: cc-context-awareness install <template>');
}
