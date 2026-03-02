/**
 * Catalog loading and remote template fetching.
 * @module src/core/templates
 */

import fs from 'fs-extra';
import path from 'path';
import { getCatalogPath } from './paths.js';
import { CLI_MAJOR_VERSION } from './constants.js';
import { CLIError } from './errors.js';
import { fetchReleases, getTemplateReleases, getLatestStableRelease, findAsset } from '../services/releases.js';
import { downloadAndExtract, cleanup } from '../services/extractor.js';

/**
 * Load the template catalog (bundled in npm package).
 * @returns {Promise<Object>} Catalog with templates array.
 */
export async function loadCatalog() {
  const catalogPath = getCatalogPath();
  return fs.readJson(catalogPath);
}

/**
 * Load a template manifest from a local install directory.
 * Used by the remove command to read the manifest saved during install.
 * @param {string} templateInstallDir - Path to .claude/{templateId}/
 * @returns {Promise<Object>} Template manifest.
 */
export async function loadLocalManifest(templateInstallDir) {
  const manifestPath = path.join(templateInstallDir, 'template.json');
  if (!await fs.pathExists(manifestPath)) {
    return null;
  }
  return fs.readJson(manifestPath);
}

/**
 * Fetch a template from GitHub Releases, download and extract it.
 * @param {string} templateId - e.g. "simple-session-memory"
 * @returns {Promise<{ tempDir: string, manifest: Object, version: string }>}
 */
export async function fetchAndExtractTemplate(templateId) {
  // Fetch all releases
  const releases = await fetchReleases();

  // Filter for this template + CLI major version
  const templateReleases = getTemplateReleases(releases, templateId, CLI_MAJOR_VERSION);
  if (templateReleases.length === 0) {
    throw CLIError.noReleasesFound(templateId);
  }

  // Pick latest stable
  const latest = getLatestStableRelease(templateReleases);
  if (!latest) {
    throw CLIError.noReleasesFound(templateId);
  }

  const { release, parsed } = latest;
  const versionStr = `${parsed.version.major}.${parsed.version.minor}.${parsed.version.patch}`;
  const assetFilename = `${templateId}-v${versionStr}.tar.gz`;

  // Find the tarball asset
  const asset = findAsset(release, assetFilename);
  if (!asset) {
    throw CLIError.downloadFailed(assetFilename, 'Asset not found in release');
  }

  // Download and extract
  const tempDir = await downloadAndExtract(asset.browser_download_url);

  // Read the manifest from extracted content
  const manifestPath = path.join(tempDir, templateId, 'template.json');
  if (!await fs.pathExists(manifestPath)) {
    cleanup(tempDir);
    throw CLIError.templateNotFound(templateId);
  }

  const manifest = await fs.readJson(manifestPath);

  return { tempDir, manifest, version: versionStr };
}
