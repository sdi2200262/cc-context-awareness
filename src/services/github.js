/**
 * GitHub API client using Node built-in https.
 * Zero external dependencies.
 * @module src/services/github
 */

import https from 'node:https';
import { execSync } from 'node:child_process';
import { GITHUB_API_BASE, OFFICIAL_REPO } from '../core/constants.js';
import { CLIError } from '../core/errors.js';

const USER_AGENT = 'cc-context-awareness-cli';
const API_TIMEOUT = 30_000;   // 30s for API calls
const ASSET_TIMEOUT = 120_000; // 120s for binary downloads

/**
 * Get a GitHub token from env or gh CLI.
 * @returns {string|null}
 */
export function getToken() {
  if (process.env.GITHUB_TOKEN) return process.env.GITHUB_TOKEN;
  try {
    return execSync('gh auth token', { encoding: 'utf-8', stdio: ['pipe', 'pipe', 'pipe'] }).trim() || null;
  } catch {
    return null;
  }
}

/**
 * Build common request headers.
 * @returns {Object}
 */
function buildHeaders() {
  const headers = {
    'User-Agent': USER_AGENT,
    'Accept': 'application/vnd.github.v3+json',
  };
  const token = getToken();
  if (token) headers['Authorization'] = `token ${token}`;
  return headers;
}

/**
 * Perform a GET request and return parsed JSON.
 * @param {string} urlPath - Path relative to GITHUB_API_BASE (e.g. "/repos/owner/repo/releases")
 * @returns {Promise<any>}
 */
export function fetchJSON(urlPath) {
  const url = urlPath.startsWith('http') ? urlPath : `${GITHUB_API_BASE}${urlPath}`;
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: buildHeaders(), timeout: API_TIMEOUT }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        // Follow redirect
        fetchJSON(res.headers.location).then(resolve, reject);
        return;
      }

      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf-8');
        if (res.statusCode !== 200) {
          reject(CLIError.networkError(url, `HTTP ${res.statusCode}: ${body.slice(0, 200)}`));
          return;
        }
        try {
          resolve(JSON.parse(body));
        } catch {
          reject(CLIError.networkError(url, 'Invalid JSON response'));
        }
      });
    });
    req.on('error', (err) => reject(CLIError.networkError(url, err.message)));
    req.on('timeout', () => { req.destroy(); reject(CLIError.networkError(url, 'Request timed out')); });
  });
}

/**
 * Download a binary asset, following redirects. Returns a Buffer.
 * @param {string} url - Full URL to download
 * @returns {Promise<Buffer>}
 */
export function fetchBuffer(url) {
  return new Promise((resolve, reject) => {
    const headers = { 'User-Agent': USER_AGENT, 'Accept': 'application/octet-stream' };
    const token = getToken();
    if (token) headers['Authorization'] = `token ${token}`;

    const req = https.get(url, { headers, timeout: ASSET_TIMEOUT }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        // Follow redirect (GitHub redirects asset downloads)
        fetchBuffer(res.headers.location).then(resolve, reject);
        return;
      }

      if (res.statusCode !== 200) {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          reject(CLIError.downloadFailed(url, `HTTP ${res.statusCode}`));
        });
        return;
      }

      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    });
    req.on('error', (err) => reject(CLIError.downloadFailed(url, err.message)));
    req.on('timeout', () => { req.destroy(); reject(CLIError.downloadFailed(url, 'Download timed out')); });
  });
}
