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
 * Interactive template selection. Supports state-aware display.
 * @param {Object} catalog
 * @param {Object} [options]
 * @param {string} [options.message] - Custom prompt message
 * @param {string|null} [options.activeTemplate] - Currently installed template ID
 * @param {boolean} [options.removeMode] - If true, only show installed template
 * @returns {Promise<string|null>} Template id or null if user went back
 */
export async function selectTemplate(catalog, options = {}) {
  logger.clearAndBanner();
  const message = options.message || 'Which template would you like to install?';
  const activeTemplate = options.activeTemplate || null;

  // In remove mode, only show the installed template
  if (options.removeMode) {
    if (!activeTemplate) {
      logger.info('No template is currently installed.');
      return null;
    }
    const active = catalog.templates.find(t => t.id === activeTemplate);
    if (!active) {
      logger.info('No template is currently installed.');
      return null;
    }
    const choices = [
      { name: `${active.name} (installed)`, value: active.id },
      { name: '\u2190 Back', value: BACK },
    ];
    const result = await select({ message, choices, clearPromptOnDone: true });
    return result === BACK ? null : result;
  }

  // Normal mode: show all templates, mark installed
  const choices = [
    ...catalog.templates.map(t => {
      const installed = t.id === activeTemplate ? ' (installed)' : '';
      return {
        name: `${t.name}${installed} \u2014 ${t.description}`,
        value: t.id,
      };
    }),
    { name: '\u2190 Back', value: BACK },
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
