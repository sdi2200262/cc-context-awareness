/**
 * Install command — base system and/or templates.
 * @module src/commands/install
 */

import fs from 'fs-extra';
import path from 'path';
import logger from '../ui/logger.js';
import { selectTemplate } from '../ui/prompts.js';
import { getPaths, getRuntimeDir, getDocsDir } from '../core/paths.js';
import { readConfig, writeConfig, createDefaultConfig, upsertThresholds } from '../core/config.js';
import { readSettings, writeSettings, setStatusLine, removeStatusLine, addHook, removeHook } from '../core/settings.js';
import { loadCatalog, loadTemplateManifest, getTemplateDir } from '../core/templates.js';
import { CLIError } from '../core/errors.js';
import { removeTemplateAssets } from './remove.js';

/**
 * Install base system or a template.
 * @param {string|undefined} templateName - Template id, or undefined for base/interactive.
 * @param {Object} options - CLI options.
 */
export async function installCommand(templateName, options = {}) {
  const isGlobal = !!options.global;
  const paths = getPaths(isGlobal);
  const scope = isGlobal ? 'global' : 'local';

  if (templateName) {
    // Direct template install — auto-install base if missing, then install template
    await ensureBaseInstalled(paths, scope, options);
    await installTemplate(templateName, paths, scope, options);
  } else {
    // Base install only
    await installBase(paths, scope, options);
  }
}

/**
 * Install the base system (runtime scripts, config, settings patches).
 * @param {Object} paths - Resolved install paths from getPaths().
 * @param {string} scope - "local" or "global".
 * @param {Object} options - CLI options.
 */
async function installBase(paths, scope, options) {
  logger.clearAndBanner();
  logger.info(`Installing base system (${scope})...`);

  const runtimeDir = getRuntimeDir();
  const docsDir = getDocsDir();

  // Create install directory
  await fs.ensureDir(paths.installDir);

  // Copy runtime scripts
  logger.info('Copying runtime scripts...');
  const scripts = ['bridge.sh', 'check-thresholds.sh', 'reset.sh'];
  for (const script of scripts) {
    await fs.copy(path.join(runtimeDir, script), path.join(paths.installDir, script));
    await fs.chmod(path.join(paths.installDir, script), 0o755);
  }
  logger.success(`Scripts installed to ${paths.installDir}`);

  // Create default config.json if none exists
  const existingConfig = await readConfig(paths.configFile);
  if (!existingConfig) {
    const config = await createDefaultConfig(paths.configFile);
    const count = (config.thresholds || []).length;
    logger.success(`Config created (${count} threshold: 80% warning)`);
  } else {
    logger.info('Existing config.json preserved');
  }

  // Patch settings
  const settings = await readSettings(paths.settingsFile);
  const bridgePath = path.join(paths.installDir, 'bridge.sh');
  const checkPath = path.join(paths.installDir, 'check-thresholds.sh');
  const resetPath = path.join(paths.installDir, 'reset.sh');

  // StatusLine — bridge
  const slResult = setStatusLine(settings, bridgePath);
  if (slResult.action === 'created') {
    logger.success(`statusLine configured: ${slResult.command}`);
  } else if (slResult.action === 'prepended') {
    logger.success(`Bridge prepended to existing statusLine`);
    logger.dim(`statusLine: ${slResult.command}`, { indent: true });
  } else {
    logger.info('statusLine already configured');
  }

  // Hooks — check-thresholds (PreToolUse) and reset (SessionStart, compact)
  const hookAdded = addHook(settings, 'PreToolUse', '', checkPath);
  if (hookAdded) {
    logger.info('Registered PreToolUse hook (check-thresholds)');
  }

  const resetAdded = addHook(settings, 'SessionStart', 'compact', resetPath);
  if (resetAdded) {
    logger.info('Registered SessionStart hook (compaction reset)');
  }

  await writeSettings(paths.settingsFile, settings);
  logger.success(`Updated ${path.basename(paths.settingsFile)}`);

  // Install skill
  if (!options.noSkill) {
    await fs.ensureDir(paths.skillDir);
    await fs.copy(path.join(docsDir, 'SKILL.md'), path.join(paths.skillDir, 'SKILL.md'));
    logger.info('Installed agent skill');
  }

  // Save install metadata
  await fs.writeJson(paths.metaFile, {
    version: '1.0.0',
    scope,
    activeTemplate: null,
    installedAt: new Date().toISOString(),
  }, { spaces: 2 });

  logger.blank();
  logger.success(`cc-context-awareness installed (${scope})!`);
  logger.dim(`Config:   ${paths.configFile}`, { indent: true });
  logger.dim(`Settings: ${paths.settingsFile}`, { indent: true });
  logger.dim('Restart Claude Code to activate.', { indent: true });
}

/**
 * Ensure base is installed, installing it if not.
 * @param {Object} paths - Resolved install paths from getPaths().
 * @param {string} scope - "local" or "global".
 * @param {Object} options - CLI options.
 */
async function ensureBaseInstalled(paths, scope, options) {
  if (!await fs.pathExists(paths.metaFile)) {
    logger.info('Base system not found — installing automatically...');
    logger.blank();
    await installBase(paths, scope, options);
    logger.blank();
  }
}

/**
 * Install a template by id — upserts thresholds, registers hooks/agents, patches CLAUDE.md.
 * @param {string} templateId
 * @param {Object} paths - Resolved install paths from getPaths().
 * @param {string} scope - "local" or "global".
 * @param {Object} options - CLI options.
 */
async function installTemplate(templateId, paths, scope, options) {
  // Validate template exists
  const catalog = await loadCatalog();
  const entry = catalog.templates.find(t => t.id === templateId);
  if (!entry) throw CLIError.templateNotFound(templateId);

  const manifest = await loadTemplateManifest(templateId);
  const templateDir = getTemplateDir(templateId);

  // Read install metadata
  const meta = await fs.readJson(paths.metaFile);

  // One-template enforcement — remove previous if different
  if (meta.activeTemplate && meta.activeTemplate !== templateId) {
    logger.blank();
    logger.warn(`"${meta.activeTemplate}" is currently active. It will be removed.`);
    await removeTemplateAssets(meta.activeTemplate, paths);
    logger.success(`Removed ${meta.activeTemplate}`);
    logger.blank();
  }

  logger.clearAndBanner();
  logger.info(`Installing template: ${entry.name} (${scope})...`);

  const settings = await readSettings(paths.settingsFile);

  // 1. Upsert thresholds
  if (manifest.thresholds_file) {
    const thresholdsPath = path.join(templateDir, manifest.thresholds_file);
    const newThresholds = await fs.readJson(thresholdsPath);
    const result = await upsertThresholds(paths.configFile, newThresholds);
    const levels = newThresholds.map(t => t.level).join(', ');
    logger.success(`Added ${newThresholds.length} thresholds (${levels})`);
  }

  // 2. Register hooks
  if (manifest.hooks && manifest.hooks.length > 0) {
    logger.info('Registering hooks...');
    const templateInstallDir = path.join(paths.claudeDir, templateId);
    await fs.ensureDir(path.join(templateInstallDir, 'hooks'));

    for (const hook of manifest.hooks) {
      const srcScript = path.join(templateDir, hook.script);
      const destScript = path.join(templateInstallDir, hook.script);
      await fs.ensureDir(path.dirname(destScript));
      await fs.copy(srcScript, destScript);
      await fs.chmod(destScript, 0o755);

      addHook(settings, hook.event, hook.matcher, destScript);
      logger.success(`Registered ${hook.script}`);
    }
  }

  // 3. Install agents
  if (manifest.agents && manifest.agents.length > 0) {
    logger.info('Installing agents...');
    for (const agent of manifest.agents) {
      const srcAgent = path.join(templateDir, agent.source);
      const destAgent = path.join(paths.claudeDir, agent.dest);
      await fs.ensureDir(path.dirname(destAgent));
      await fs.copy(srcAgent, destAgent);
      logger.success(`Installed ${path.basename(agent.dest)}`);
    }
  }

  // 4. Create directories
  if (manifest.directories && manifest.directories.length > 0) {
    logger.info('Creating directories...');
    for (const dir of manifest.directories) {
      const dirPath = path.join(paths.claudeDir, dir);
      await fs.ensureDir(dirPath);
    }
    const dirList = manifest.directories.map(d => `.claude/${d}/`).join(', ');
    logger.success(`Created ${dirList}`);
  }

  // 5. Write settings
  await writeSettings(paths.settingsFile, settings);

  // 6. Patch CLAUDE.md
  if (!options.noClaudeMd && manifest.claude_snippet) {
    const snippetPath = path.join(templateDir, manifest.claude_snippet);
    const claudeMdPath = path.join(process.cwd(), 'CLAUDE.md');
    const marker = manifest.claude_snippet_marker;

    if (await fs.pathExists(snippetPath)) {
      const snippet = await fs.readFile(snippetPath, 'utf-8');

      if (await fs.pathExists(claudeMdPath)) {
        const existing = await fs.readFile(claudeMdPath, 'utf-8');
        if (marker && existing.includes(marker)) {
          logger.info('CLAUDE.md: instructions already present (skipped)');
        } else {
          await fs.appendFile(claudeMdPath, `\n---\n\n${snippet}`);
          logger.success('Appended instructions to CLAUDE.md');
        }
      } else {
        await fs.writeFile(claudeMdPath, snippet);
        logger.success('Created CLAUDE.md with template instructions');
      }
    }
  }

  // 7. Update install metadata
  meta.activeTemplate = templateId;
  await fs.writeJson(paths.metaFile, meta, { spaces: 2 });

  logger.blank();
  logger.success(`${entry.name} installed!`);
  logger.dim('Restart Claude Code to activate.', { indent: true });
}
