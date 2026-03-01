/**
 * Catalog and template manifest loading.
 * @module src/core/templates
 */

import fs from 'fs-extra';
import path from 'path';
import { getTemplatesDir } from './paths.js';
import { CLIError } from './errors.js';

/**
 * Load the template catalog.
 * @returns {Promise<Object>} Catalog with templates array.
 */
export async function loadCatalog() {
  const catalogPath = path.join(getTemplatesDir(), 'catalog.json');
  return fs.readJson(catalogPath);
}

/**
 * Load a template's manifest (template.json).
 * @param {string} templateId
 * @returns {Promise<Object>} Template manifest.
 */
export async function loadTemplateManifest(templateId) {
  const manifestPath = path.join(getTemplatesDir(), templateId, 'template.json');
  if (!await fs.pathExists(manifestPath)) {
    throw CLIError.templateNotFound(templateId);
  }
  return fs.readJson(manifestPath);
}

/**
 * Resolve the template directory path within the package.
 * @param {string} templateId
 * @returns {string}
 */
export function getTemplateDir(templateId) {
  return path.join(getTemplatesDir(), templateId);
}
