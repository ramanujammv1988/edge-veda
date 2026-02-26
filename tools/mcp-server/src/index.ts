#!/usr/bin/env node

/**
 * Edge Veda MCP Server
 *
 * Provides 6 tools for Claude Code to automate Edge Veda Flutter project
 * setup end-to-end via MCP stdio transport.
 *
 * Tools:
 *   edge_veda_check_environment  - Verify dev prerequisites
 *   edge_veda_list_models        - Device-aware model recommendations
 *   edge_veda_create_project     - Scaffold a Flutter project
 *   edge_veda_download_model     - Download a model GGUF file
 *   edge_veda_add_capability     - Add capability code scaffolding
 *   edge_veda_run                - Build and deploy to device
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

import { registerCheckEnvironment } from "./tools/check-environment.js";
import { registerListModels } from "./tools/list-models.js";
import { registerCreateProject } from "./tools/create-project.js";
import { registerDownloadModel } from "./tools/download-model.js";
import { registerAddCapability } from "./tools/add-capability.js";
import { registerRun } from "./tools/run.js";

const server = new McpServer({
  name: "edge-veda",
  version: "0.1.0",
});

// Register all 6 tools
registerCheckEnvironment(server);
registerListModels(server);
registerCreateProject(server);
registerDownloadModel(server);
registerAddCapability(server);
registerRun(server);

// Connect via stdio transport (JSON-RPC over stdin/stdout)
const transport = new StdioServerTransport();
await server.connect(transport);

// Log to stderr ONLY -- stdout is reserved for JSON-RPC
console.error("Edge Veda MCP server started (stdio transport)");
