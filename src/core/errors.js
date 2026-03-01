/**
 * CLI Error Classes
 * @module src/core/errors
 */

/** @enum {string} Error codes for CLI operations. */
export const CLIErrorCode = {
  TEMPLATE_NOT_FOUND: 'TEMPLATE_NOT_FOUND',
  BASE_NOT_INSTALLED: 'BASE_NOT_INSTALLED',
  CONFIG_CORRUPTED: 'CONFIG_CORRUPTED',
  SETTINGS_CORRUPTED: 'SETTINGS_CORRUPTED',
  ALREADY_INSTALLED: 'ALREADY_INSTALLED',
  NOTHING_TO_REMOVE: 'NOTHING_TO_REMOVE',
  NOT_INSTALLED: 'NOT_INSTALLED',
};

export class CLIError extends Error {
  /**
   * @param {string} message
   * @param {string} code - Error code from CLIErrorCode.
   * @param {Object} [context={}]
   */
  constructor(message, code, context = {}) {
    super(message);
    this.name = 'CLIError';
    this.code = code;
    this.context = context;
  }

  /** @returns {{ name: string, message: string, code: string, context: Object }} */
  toJSON() {
    return {
      name: this.name,
      message: this.message,
      code: this.code,
      context: this.context,
    };
  }

  /**
   * @param {string} id - Template identifier.
   * @returns {CLIError}
   */
  static templateNotFound(id) {
    return new CLIError(
      `Template "${id}" not found. Run "cc-context-awareness list" to see available templates.`,
      CLIErrorCode.TEMPLATE_NOT_FOUND,
      { id }
    );
  }

  /** @returns {CLIError} */
  static baseNotInstalled() {
    return new CLIError(
      'cc-context-awareness is not installed. Run "cc-context-awareness install" first.',
      CLIErrorCode.BASE_NOT_INSTALLED
    );
  }

  /**
   * @param {string} path - Path to the corrupted config file.
   * @returns {CLIError}
   */
  static configCorrupted(path) {
    return new CLIError(
      `Config file contains invalid JSON: ${path}\nFix the file manually and re-run.`,
      CLIErrorCode.CONFIG_CORRUPTED,
      { path }
    );
  }

  /**
   * @param {string} path - Path to the corrupted settings file.
   * @returns {CLIError}
   */
  static settingsCorrupted(path) {
    return new CLIError(
      `Settings file contains invalid JSON: ${path}\nFix the file manually and re-run.`,
      CLIErrorCode.SETTINGS_CORRUPTED,
      { path }
    );
  }

  /** @returns {CLIError} */
  static notInstalled() {
    return new CLIError(
      'cc-context-awareness is not installed here.',
      CLIErrorCode.NOT_INSTALLED
    );
  }
}

export default CLIError;
