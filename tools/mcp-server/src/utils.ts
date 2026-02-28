import { exec as execCb, execFile as execFileCb, execSync as execSyncNative } from "node:child_process";

export interface ExecResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

/**
 * Execute a command asynchronously, capturing stdout/stderr without throwing
 * on non-zero exit codes.
 */
export function exec(cmd: string): Promise<ExecResult> {
  return new Promise((resolve) => {
    execCb(cmd, { maxBuffer: 10 * 1024 * 1024 }, (error, stdout, stderr) => {
      resolve({
        stdout: stdout?.toString() ?? "",
        stderr: stderr?.toString() ?? "",
        exitCode: error?.code ?? (error ? 1 : 0),
      });
    });
  });
}

/**
 * Execute a command synchronously, returning stdout as a string.
 * Throws on non-zero exit code.
 */
export function execSyncStr(cmd: string): string {
  return execSyncNative(cmd, { encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 }).trim();
}

/**
 * Execute a command asynchronously using execFile (no shell interpolation).
 * Arguments are passed as an array, preventing command injection.
 */
export function execFileAsync(
  bin: string,
  args: string[],
  opts?: { cwd?: string },
): Promise<ExecResult> {
  return new Promise((resolve) => {
    execFileCb(
      bin,
      args,
      { maxBuffer: 10 * 1024 * 1024, cwd: opts?.cwd },
      (error, stdout, stderr) => {
        resolve({
          stdout: stdout?.toString() ?? "",
          stderr: stderr?.toString() ?? "",
          exitCode: typeof error?.code === "number" ? error.code : (error ? 1 : 0),
        });
      },
    );
  });
}

/**
 * Validate a Flutter project name (lowercase, underscores, starts with letter).
 * Throws if the name contains characters that could be used for injection.
 */
export function validateProjectName(name: string): void {
  if (!/^[a-z][a-z0-9_]*$/.test(name)) {
    throw new Error(
      `Invalid project name "${name}": must match /^[a-z][a-z0-9_]*$/ (lowercase letters, digits, underscores, starting with a letter)`,
    );
  }
}

/**
 * Validate a device ID (alphanumeric, dots, hyphens, underscores).
 * Throws if the ID contains characters that could be used for injection.
 */
export function validateDeviceId(id: string): void {
  if (!/^[a-zA-Z0-9._-]+$/.test(id)) {
    throw new Error(
      `Invalid device ID "${id}": must match /^[a-zA-Z0-9._-]+$/`,
    );
  }
}

/**
 * Validate a project path does not contain path traversal segments.
 * Throws if the path contains ".." which could escape intended directories.
 */
export function validateProjectPath(p: string): void {
  if (p.includes("..")) {
    throw new Error(
      `Invalid project path "${p}": must not contain ".." segments`,
    );
  }
}
