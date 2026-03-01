/**
 * CLI Logging Module
 * @module src/ui/logger
 */

import chalk from 'chalk';

const LOG_LEVELS = {
  INFO: chalk.white,
  WARN: chalk.yellow,
  ERROR: chalk.red,
  SUCCESS: chalk.green,
};

const PREFIX_WIDTH = 9;
const INDENT = '  ';

/**
 * Log an info message.
 * @param {string} message
 * @param {Object} [options]
 * @param {boolean} [options.indent] - Indent the message.
 */
export function info(message, options = {}) {
  const prefix = LOG_LEVELS.INFO('[INFO]'.padEnd(PREFIX_WIDTH));
  const formatted = options.indent ? `${INDENT}${message}` : message;
  console.log(`${prefix} ${formatted}`);
}

/**
 * Log a warning message.
 * @param {string} message
 * @param {Object} [options]
 * @param {boolean} [options.indent]
 */
export function warn(message, options = {}) {
  const prefix = LOG_LEVELS.WARN('[WARN]'.padEnd(PREFIX_WIDTH));
  const formatted = options.indent ? `${INDENT}${message}` : message;
  console.log(`${prefix} ${formatted}`);
}

/**
 * Log an error message. Optionally prints a stack trace.
 * @param {string} message
 * @param {Object} [options]
 * @param {boolean} [options.indent]
 * @param {Error} [options.error] - Error object whose stack will be printed.
 */
export function error(message, options = {}) {
  const prefix = LOG_LEVELS.ERROR('[ERROR]'.padEnd(PREFIX_WIDTH));
  const formatted = options.indent ? `${INDENT}${message}` : message;
  console.error(`${prefix} ${formatted}`);

  if (options.error?.stack) {
    console.error(chalk.gray(options.error.stack));
  }
}

/**
 * Log a success message.
 * @param {string} message
 * @param {Object} [options]
 * @param {boolean} [options.indent]
 */
export function success(message, options = {}) {
  const prefix = LOG_LEVELS.SUCCESS('[SUCCESS]'.padEnd(PREFIX_WIDTH));
  const formatted = options.indent ? `${INDENT}${message}` : message;
  console.log(`${prefix} ${formatted}`);
}

/**
 * Log a dimmed (gray) message.
 * @param {string} message
 * @param {Object} [options]
 * @param {boolean} [options.indent]
 */
export function dim(message, options = {}) {
  const formatted = options.indent ? `${INDENT}${message}` : message;
  console.log(chalk.gray(formatted));
}

/** Print a blank line. */
export function blank() {
  console.log('');
}

/**
 * Print a horizontal separator line.
 * @param {number} [length=50]
 */
export function line(length = 50) {
  console.log(chalk.gray('─'.repeat(length)));
}

/** Print the CLI banner with name, version, and tagline. */
export function banner() {
  const pkg = { version: '1.0.0' };
  const tagline = 'Tell Claude what to do based on how much context it has used.';
  console.log('');
  console.log(chalk.white.bold('cc-context-awareness') + chalk.gray(` v${pkg.version}`) + chalk.dim('  — by CobuterMan 🖥'));
  console.log(chalk.gray(tagline));
  console.log('');
  console.log(chalk.gray('─'.repeat(tagline.length)));
  console.log('');
}

/** Clear the terminal and print the banner. */
export function clearAndBanner() {
  console.clear();
  banner();
}

export default {
  info,
  warn,
  error,
  success,
  dim,
  blank,
  line,
  banner,
  clearAndBanner,
  chalk,
};
