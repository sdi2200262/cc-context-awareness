/**
 * Interactive prompts using @inquirer/prompts.
 * @module src/ui/prompts
 */

import { select, confirm } from '@inquirer/prompts';
import logger from './logger.js';

const BACK = Symbol('back');

/**
 * Main menu when no subcommand given.
 * @returns {Promise<'install-base'|'install-template'|'remove'|'status'|'uninstall'>}
 */
export async function selectAction() {
  logger.clearAndBanner();
  return select({
    message: 'What would you like to do?',
    choices: [
      { name: 'Install base system', value: 'install-base' },
      { name: 'Install a template', value: 'install-template' },
      { name: 'Remove a template', value: 'remove' },
      { name: 'Show status', value: 'status' },
      { name: 'Uninstall everything', value: 'uninstall' },
      { name: 'Exit', value: 'exit' },
    ],
    clearPromptOnDone: true,
  });
}

/**
 * Interactive template selection.
 * @param {Object} catalog
 * @param {Object} [options]
 * @param {string} [options.message] - Custom prompt message
 * @returns {Promise<string|null>} Template id or null if user went back
 */
export async function selectTemplate(catalog, options = {}) {
  logger.clearAndBanner();
  const message = options.message || 'Which template would you like to install?';
  const choices = [
    ...catalog.templates.map(t => ({
      name: `${t.name} — ${t.description}`,
      value: t.id,
    })),
    { name: '← Back', value: BACK },
  ];
  const result = await select({
    message,
    choices,
    clearPromptOnDone: true,
  });
  return result === BACK ? null : result;
}

export { BACK };

/**
 * Confirm before destructive operations.
 * @param {string} message - Confirmation prompt text.
 * @param {boolean} [defaultValue=false] - Default answer.
 * @returns {Promise<boolean>}
 */
export async function confirmAction(message, defaultValue = false) {
  return confirm({ message, default: defaultValue });
}
