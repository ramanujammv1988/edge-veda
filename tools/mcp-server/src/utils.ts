import { exec as execCb, execSync as execSyncNative } from "node:child_process";

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
