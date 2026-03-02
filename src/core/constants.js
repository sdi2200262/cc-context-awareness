/**
 * CLI constants — version, repo metadata.
 * @module src/core/constants
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PKG_ROOT = path.resolve(__dirname, '..', '..');

const pkg = JSON.parse(fs.readFileSync(path.join(PKG_ROOT, 'package.json'), 'utf-8'));

/** Full CLI version string from package.json (e.g. "1.1.0"). */
export const CLI_VERSION = pkg.version;

/** CLI major version number (e.g. 1). Used to gate template compatibility. */
export const CLI_MAJOR_VERSION = parseInt(CLI_VERSION.split('.')[0], 10);

/** Official GitHub repository coordinates. */
export const OFFICIAL_REPO = { owner: 'sdi2200262', repo: 'cc-context-awareness' };

/** GitHub API base URL. */
export const GITHUB_API_BASE = 'https://api.github.com';
