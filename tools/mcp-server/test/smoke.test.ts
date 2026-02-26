/**
 * MCP Server Smoke Test
 *
 * Validates the server starts, responds to JSON-RPC, lists all 6 tools,
 * and executes check_environment and list_models tools.
 */

import { describe, it, after, before } from "node:test";
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVER_PATH = join(__dirname, "..", "build", "index.js");

let serverProcess: ChildProcess;
let messageId = 0;

function nextId(): number {
  return ++messageId;
}

/**
 * Send a JSON-RPC message to the server and wait for a response.
 */
function sendAndReceive(
  proc: ChildProcess,
  method: string,
  params: Record<string, unknown> = {},
): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    const id = nextId();
    const message = JSON.stringify({ jsonrpc: "2.0", id, method, params });

    let buffer = "";
    const timeout = setTimeout(() => {
      proc.stdout?.removeListener("data", onData);
      reject(new Error(`Timeout waiting for response to ${method} (id: ${id})`));
    }, 15000);

    function onData(data: Buffer) {
      buffer += data.toString();

      // Try to parse complete JSON-RPC messages
      const lines = buffer.split("\n");
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          const parsed = JSON.parse(trimmed);
          if (parsed.id === id) {
            clearTimeout(timeout);
            proc.stdout?.removeListener("data", onData);
            resolve(parsed);
            return;
          }
        } catch {
          // Not a complete JSON message yet, continue buffering
        }
      }
    }

    proc.stdout?.on("data", onData);
    proc.stdin?.write(message + "\n");
  });
}

describe("Edge Veda MCP Server", () => {
  before(() => {
    serverProcess = spawn("node", [SERVER_PATH], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Collect stderr for debugging
    serverProcess.stderr?.on("data", (data: Buffer) => {
      // Server logs to stderr - that is expected
    });
  });

  after(() => {
    if (serverProcess) {
      serverProcess.kill("SIGTERM");
    }
  });

  it("should respond to initialize", async () => {
    const response = await sendAndReceive(serverProcess, "initialize", {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "smoke-test", version: "1.0.0" },
    });

    assert.equal(response.jsonrpc, "2.0");
    assert.ok(response.result, "Should have a result");

    const result = response.result as Record<string, unknown>;
    assert.ok(result.serverInfo, "Should have serverInfo");

    const serverInfo = result.serverInfo as Record<string, string>;
    assert.equal(serverInfo.name, "edge-veda");
    assert.equal(serverInfo.version, "0.1.0");

    // Send initialized notification (no response expected)
    serverProcess.stdin?.write(
      JSON.stringify({
        jsonrpc: "2.0",
        method: "notifications/initialized",
      }) + "\n",
    );

    // Brief pause for notification processing
    await new Promise((r) => setTimeout(r, 200));
  });

  it("should list all 6 tools", async () => {
    const response = await sendAndReceive(serverProcess, "tools/list", {});

    assert.ok(response.result, "Should have a result");
    const result = response.result as { tools: Array<{ name: string }> };
    assert.ok(Array.isArray(result.tools), "Should have tools array");

    const toolNames = result.tools.map((t) => t.name).sort();
    const expectedTools = [
      "edge_veda_add_capability",
      "edge_veda_check_environment",
      "edge_veda_create_project",
      "edge_veda_download_model",
      "edge_veda_list_models",
      "edge_veda_run",
    ];

    assert.deepEqual(toolNames, expectedTools, "All 6 tools should be registered");
  });

  it("should execute check_environment and report Flutter status", async () => {
    const response = await sendAndReceive(serverProcess, "tools/call", {
      name: "edge_veda_check_environment",
      arguments: {},
    });

    assert.ok(response.result, "Should have a result");
    const result = response.result as {
      content: Array<{ type: string; text: string }>;
    };
    assert.ok(Array.isArray(result.content), "Should have content array");
    assert.ok(result.content.length > 0, "Should have content");

    const text = result.content[0].text;
    assert.ok(
      text.includes("Flutter"),
      `check_environment should mention Flutter, got: ${text.slice(0, 200)}`,
    );
    assert.ok(
      text.includes("Xcode"),
      `check_environment should mention Xcode`,
    );
  });

  it("should execute list_models with chat use case and return llama models", async () => {
    const response = await sendAndReceive(serverProcess, "tools/call", {
      name: "edge_veda_list_models",
      arguments: { use_case: "chat" },
    });

    assert.ok(response.result, "Should have a result");
    const result = response.result as {
      content: Array<{ type: string; text: string }>;
    };
    assert.ok(result.content.length > 0, "Should have content");

    const text = result.content[0].text.toLowerCase();
    assert.ok(
      text.includes("llama"),
      `list_models for chat should include llama models, got: ${text.slice(0, 300)}`,
    );
    assert.ok(
      text.includes("recommended"),
      `list_models should show recommended model`,
    );
  });
});
