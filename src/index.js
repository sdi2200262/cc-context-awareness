#!/usr/bin/env node

/**
 * cc-context-awareness CLI entry point.
 * @module src/index
 */

import fs from 'fs-extra';
import { program } from 'commander';
import { installCommand } from './commands/install.js';
import { removeCommand } from './commands/remove.js';
import { listCommand } from './commands/list.js';
import { statusCommand } from './commands/status.js';
import { uninstallCommand } from './commands/uninstall.js';
import { selectAction, selectTemplate } from './ui/prompts.js';
import { loadCatalog } from './core/templates.js';
import { getPaths } from './core/paths.js';
import { CLIError } from './core/errors.js';
import { CLI_VERSION } from './core/constants.js';
import logger from './ui/logger.js';

/**
 * Read install metadata to get active template info.
 * @returns {Promise<{ activeTemplate: string|null, activeTemplateVersion: string|null }>}
 */
async function getInstallState() {
  for (const global of [false, true]) {
    const paths = getPaths(global);
    try {
      if (await fs.pathExists(paths.metaFile)) {
        const meta = await fs.readJson(paths.metaFile);
        return {
          activeTemplate: meta.activeTemplate || null,
          activeTemplateVersion: meta.activeTemplateVersion || null,
        };
      }
    } catch {
      // Ignore read errors
    }
  }
  return { activeTemplate: null, activeTemplateVersion: null };
}

/**
 * Handle CLI errors — print message and exit.
 * @param {Error} err
 */
function handleError(err) {
  if (err instanceof CLIError) {
    logger.error(err.message);
  } else if (err.message?.includes('User force closed')) {
    // Inquirer cancellation — exit silently
    process.exit(0);
  } else {
    logger.error('An unexpected error occurred.', { error: err });
  }
  process.exit(1);
}

program
  .name('cc-context-awareness')
  .description('Configurable context window thresholds for Claude Code')
  .version(CLI_VERSION);

program
  .command('install [template]')
  .description('Install base system, or install a template')
  .option('--global', 'Install to ~/.claude/ instead of ./.claude/')
  .option('--no-claude-md', 'Skip CLAUDE.md modification')
  .option('--no-skill', 'Skip agent skill installation')
  .action(async (template, options) => {
    try {
      if (!template && process.stdin.isTTY) {
        // Interactive: ask if they want to pick a template
        const catalog = await loadCatalog();
        const { activeTemplate } = await getInstallState();
        const selected = await selectTemplate(catalog, { activeTemplate });
        if (!selected) return; // user went back — nothing to go back to in subcommand mode
        await installCommand(selected, options);
      } else {
        await installCommand(template, options);
      }
    } catch (err) {
      handleError(err);
    }
  });

program
  .command('remove [template]')
  .description('Remove a template')
  .option('--global', 'Target ~/.claude/')
  .action(async (template, options) => {
    try {
      if (!template && process.stdin.isTTY) {
        // Interactive: show only installed template
        const catalog = await loadCatalog();
        const { activeTemplate } = await getInstallState();
        const selected = await selectTemplate(catalog, {
          message: 'Which template would you like to remove?',
          activeTemplate,
          removeMode: true,
        });
        if (!selected) return;
        await removeCommand(selected, options);
      } else if (template) {
        await removeCommand(template, options);
      } else {
        logger.error('Template name required in non-interactive mode.');
        process.exit(1);
      }
    } catch (err) {
      handleError(err);
    }
  });

program
  .command('list')
  .description('Available templates')
  .action(async () => {
    try {
      await listCommand();
    } catch (err) {
      handleError(err);
    }
  });

program
  .command('status')
  .description('Show what\'s installed')
  .option('--global', 'Target ~/.claude/')
  .action(async (options) => {
    try {
      await statusCommand(options);
    } catch (err) {
      handleError(err);
    }
  });

program
  .command('uninstall')
  .description('Remove everything')
  .option('--global', 'Target ~/.claude/')
  .action(async (options) => {
    try {
      await uninstallCommand(options);
    } catch (err) {
      handleError(err);
    }
  });

// Default action (no subcommand) → interactive menu
program.action(async () => {
  try {
    if (!process.stdin.isTTY) {
      // Non-interactive: just install base
      await installCommand(undefined, {});
      return;
    }

    let running = true;
    while (running) {
      running = false;
      const action = await selectAction();

      switch (action) {
        case 'install-base':
          await installCommand(undefined, {});
          break;
        case 'install-template': {
          const catalog = await loadCatalog();
          const { activeTemplate } = await getInstallState();
          const selected = await selectTemplate(catalog, { activeTemplate });
          if (!selected) { running = true; break; }
          await installCommand(selected, {});
          break;
        }
        case 'remove': {
          const catalog = await loadCatalog();
          const { activeTemplate } = await getInstallState();
          if (!activeTemplate) {
            logger.clearAndBanner();
            logger.info('No template is currently installed.');
            running = true;
            break;
          }
          const selected = await selectTemplate(catalog, {
            message: 'Which template would you like to remove?',
            activeTemplate,
            removeMode: true,
          });
          if (!selected) { running = true; break; }
          await removeCommand(selected, {});
          break;
        }
        case 'status':
          await statusCommand({});
          break;
        case 'uninstall':
          await uninstallCommand({});
          break;
        case 'exit':
          break;
      }
    }
  } catch (err) {
    handleError(err);
  }
});

program.parse();
