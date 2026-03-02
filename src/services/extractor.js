/**
 * Download and extract template tar.gz archives.
 * Uses node:https (via github.js) + shell tar.
 * @module src/services/extractor
 */

import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { fetchBuffer } from './github.js';
import { CLIError } from '../core/errors.js';

/**
 * Download a tar.gz asset and extract it to a temp directory.
 * @param {string} assetUrl - URL to download the tar.gz from
 * @returns {Promise<string>} Path to the temp directory containing extracted files
 */
export async function downloadAndExtract(assetUrl) {
  // Create temp directory
  const tmpBase = path.join(os.tmpdir(), 'cc-ctx-');
  const tempDir = fs.mkdtempSync(tmpBase);
  const tarPath = path.join(tempDir, 'template.tar.gz');

  try {
    // Download the asset
    const buffer = await fetchBuffer(assetUrl);
    fs.writeFileSync(tarPath, buffer);

    // Extract with tar
    execSync(`tar xzf "${tarPath}" -C "${tempDir}"`, { stdio: 'pipe' });

    // Clean up the tarball, keep extracted content
    fs.unlinkSync(tarPath);

    return tempDir;
  } catch (err) {
    // Clean up on failure
    cleanup(tempDir);
    if (err instanceof CLIError) throw err;
    throw CLIError.downloadFailed(assetUrl, err.message);
  }
}

/**
 * Remove a temp directory after install completes.
 * @param {string} tempDir - Path to temp directory
 */
export function cleanup(tempDir) {
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {
    // Best-effort cleanup
  }
}
