/**
 * GitHub Releases — per-template tag parsing and release discovery.
 * @module src/services/releases
 */

import { fetchJSON } from './github.js';
import { OFFICIAL_REPO } from '../core/constants.js';
import { CLIError } from '../core/errors.js';

/**
 * Parse a per-template release tag.
 * Format: {id}-v{major}.{minor}.{patch}[-prerelease]
 * @param {string} tag - e.g. "simple-session-memory-v1.0.0"
 * @returns {{ templateId: string, version: { major: number, minor: number, patch: number, prerelease: string|null } } | null}
 */
export function parseTemplateTag(tag) {
  // Match: anything-vX.Y.Z or anything-vX.Y.Z-prerelease
  const match = tag.match(/^(.+)-v(\d+)\.(\d+)\.(\d+)(?:-(.+))?$/);
  if (!match) return null;
  return {
    templateId: match[1],
    version: {
      major: parseInt(match[2], 10),
      minor: parseInt(match[3], 10),
      patch: parseInt(match[4], 10),
      prerelease: match[5] || null,
    },
  };
}

/**
 * Fetch all releases from the official repo.
 * @returns {Promise<Array>} Array of GitHub release objects.
 */
export async function fetchReleases() {
  const { owner, repo } = OFFICIAL_REPO;
  return fetchJSON(`/repos/${owner}/${repo}/releases`);
}

/**
 * Filter releases for a specific template and CLI major version.
 * @param {Array} releases - All releases from fetchReleases()
 * @param {string} templateId - e.g. "simple-session-memory"
 * @param {number} majorVersion - CLI major version (e.g. 1)
 * @returns {Array<{ release: Object, parsed: Object }>} Matching releases with parsed tag info.
 */
export function getTemplateReleases(releases, templateId, majorVersion) {
  const results = [];
  for (const release of releases) {
    const parsed = parseTemplateTag(release.tag_name);
    if (!parsed) continue;
    if (parsed.templateId !== templateId) continue;
    if (parsed.version.major !== majorVersion) continue;
    results.push({ release, parsed });
  }
  return results;
}

/**
 * Find the latest stable release (no prerelease suffix) from a filtered list.
 * Uses semver comparison (major.minor.patch).
 * @param {Array<{ release: Object, parsed: Object }>} templateReleases - From getTemplateReleases()
 * @returns {{ release: Object, parsed: Object } | null}
 */
export function getLatestStableRelease(templateReleases) {
  const stable = templateReleases.filter(r => !r.parsed.version.prerelease);
  if (stable.length === 0) return null;

  return stable.reduce((best, current) => {
    const bv = best.parsed.version;
    const cv = current.parsed.version;
    if (cv.major > bv.major) return current;
    if (cv.major < bv.major) return best;
    if (cv.minor > bv.minor) return current;
    if (cv.minor < bv.minor) return best;
    if (cv.patch > bv.patch) return current;
    return best;
  });
}

/**
 * Find a specific asset by filename within a release.
 * @param {Object} release - GitHub release object
 * @param {string} filename - Asset filename to find
 * @returns {Object|null} Asset object or null
 */
export function findAsset(release, filename) {
  if (!release.assets) return null;
  return release.assets.find(a => a.name === filename) || null;
}
