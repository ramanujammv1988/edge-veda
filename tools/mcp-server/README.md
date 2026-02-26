# Edge Veda MCP Server for Claude Code

An MCP (Model Context Protocol) server that lets Claude Code automate Edge Veda Flutter project setup end-to-end. Instead of following a 20-step quickstart manually, just tell Claude Code what you want to build and the MCP tools handle environment checks, project scaffolding, model selection, and device deployment.

## What This Does

Reduces the 3-hour beginner journey to ~15 minutes by providing 6 tools that Claude Code calls automatically:

1. **Check environment** -- verify Flutter, Xcode, CocoaPods, iOS device
2. **List models** -- device-aware recommendations with memory fit estimates
3. **Create project** -- scaffold Flutter project with Edge Veda configured
4. **Download model** -- fetch the right GGUF file for the use case
5. **Add capability** -- inject code scaffolding for chat, vision, STT, TTS, image, RAG
6. **Run** -- build and deploy to connected iOS device

## Prerequisites

- Node.js >= 18
- Flutter SDK
- Xcode (for iOS development)
- CocoaPods

## Installation

```bash
cd tools/mcp-server
npm install
npm run build
```

This compiles TypeScript to `build/` and makes the `edge-veda-mcp` binary available.

## Configuration

### Claude Code (recommended)

Add to your project's `.mcp.json` (or `~/.claude.json` for global access):

```json
{
  "mcpServers": {
    "edge-veda": {
      "command": "node",
      "args": ["/absolute/path/to/edge/tools/mcp-server/build/index.js"]
    }
  }
}
```

Replace `/absolute/path/to/edge` with the actual path to this repository.

### Claude Desktop

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "edge-veda": {
      "command": "node",
      "args": ["/absolute/path/to/edge/tools/mcp-server/build/index.js"]
    }
  }
}
```

## Available Tools

| Tool | Description | Key Parameters |
|------|-------------|---------------|
| `edge_veda_check_environment` | Verify dev prerequisites are installed | (none) |
| `edge_veda_list_models` | List models with device-aware recommendations | `use_case?`, `show_all?` |
| `edge_veda_create_project` | Scaffold a Flutter project with Edge Veda | `project_name`, `path?` |
| `edge_veda_download_model` | Download a model GGUF file | `model_id`, `project_path` |
| `edge_veda_add_capability` | Add capability code scaffolding | `capability`, `project_path` |
| `edge_veda_run` | Build and deploy to iOS device | `project_path`, `mode?`, `device_id?` |

### Tool Details

#### edge_veda_check_environment

No parameters. Checks for Flutter SDK, Xcode, CocoaPods, and connected iOS devices. Returns a pass/fail report.

#### edge_veda_list_models

- `use_case` (optional): Filter by `chat`, `vision`, `stt`, `tts`, `image`, `embedding`, `tool-calling`
- `show_all` (optional): Include projector files and large desktop models

Returns a table of models with size, estimated memory usage, device fit status, and the recommended pick.

#### edge_veda_create_project

- `project_name` (required): Flutter project name (lowercase_with_underscores)
- `path` (optional): Parent directory (defaults to cwd)

Runs `flutter create`, adds `edge_veda: ^2.4.2` to pubspec.yaml, sets iOS 13.0 minimum, runs `pod install`, and writes a working boilerplate `main.dart` with model download + streaming inference.

#### edge_veda_download_model

- `model_id` (required): Model ID from `edge_veda_list_models` (e.g., `llama-3.2-1b-instruct-q4`)
- `project_path` (required): Path to the Flutter project

Downloads the model file to `/tmp/` using curl. Provides import instructions for using pre-downloaded files.

#### edge_veda_add_capability

- `capability` (required): One of `chat`, `vision`, `stt`, `tts`, `image`, `rag`
- `project_path` (required): Path to the Flutter project

Creates a new screen file (`lib/{capability}_screen.dart`) with complete working code. Lists required models that need downloading. Adds extra dependencies to pubspec.yaml if needed.

#### edge_veda_run

- `project_path` (required): Path to the Flutter project
- `mode` (optional): `debug`, `profile`, or `release` (defaults to `release`)
- `device_id` (optional): Device UDID (auto-detects connected device)

Builds and deploys the app. Defaults to release mode for optimal inference speed (~42 tok/s vs ~5 tok/s in debug).

## Example Workflow

Here is a natural language conversation showing how Claude Code uses the tools:

**You:** "I want to build an iOS app with on-device chat"

**Claude Code:**
1. Calls `edge_veda_check_environment` -- verifies Flutter, Xcode, CocoaPods are installed
2. Calls `edge_veda_create_project` with `project_name: "my_chat_app"` -- scaffolds the project
3. Calls `edge_veda_list_models` with `use_case: "chat"` -- shows Llama 3.2 1B as recommended
4. Calls `edge_veda_run` with `project_path: "./my_chat_app"` -- deploys to your iPhone

The boilerplate `main.dart` auto-downloads the model on first launch, so the app is ready to chat.

**You:** "Add vision capability too"

**Claude Code:**
1. Calls `edge_veda_add_capability` with `capability: "vision"` -- creates `lib/vision_screen.dart`
2. Calls `edge_veda_download_model` with `model_id: "smolvlm2-500m-video-instruct-q8"` -- pre-downloads the model
3. Calls `edge_veda_run` -- rebuilds and deploys the updated app

## Supported Models

The MCP server includes the complete Edge Veda model registry:

**Text/Chat:** Llama 3.1 8B, Mistral Nemo 12B, Llama 3.2 1B, Phi 3.5 Mini, Gemma 2 2B, TinyLlama 1.1B, Qwen3 0.6B

**Vision:** SmolVLM2 500M, LLaVA 1.6 Mistral 7B, Qwen2-VL 7B (each with mmproj)

**Speech-to-Text:** Whisper Tiny/Base (English), Whisper Small/Medium/Large v3 (Multilingual)

**Embedding:** All MiniLM L6 v2, Nomic Embed Text, mxbai-embed-large

**Image Generation:** SD v2.1 Turbo, SDXL Turbo, FLUX.1 Schnell

## Troubleshooting

### Server does not start

Ensure Node.js >= 18 is installed:
```bash
node --version
```

Rebuild if needed:
```bash
cd tools/mcp-server && npm run build
```

### Tools not appearing in Claude Code

1. Verify the path in `.mcp.json` is absolute and correct
2. Restart Claude Code after changing MCP configuration
3. Check server starts manually: `node build/index.js` (should hang waiting for JSON-RPC on stdin)

### flutter create fails

Ensure Flutter is on your PATH:
```bash
flutter doctor
```

### pod install fails

Clear CocoaPods cache and retry:
```bash
cd ios && pod deintegrate && pod install
```

## Architecture

```
tools/mcp-server/
  src/
    index.ts              # MCP server entry point (stdio transport)
    utils.ts              # exec helpers
    model-registry.ts     # TypeScript mirror of Dart ModelRegistry
    device-profile.ts     # Device tier detection + memory estimation
    tools/
      check-environment.ts
      create-project.ts
      list-models.ts
      download-model.ts
      add-capability.ts
      run.ts
  build/                  # Compiled JS output
  test/
    smoke.test.ts         # MCP protocol smoke test
```

The server uses the official MCP SDK (`@modelcontextprotocol/sdk`) with stdio transport. All communication happens over stdin/stdout using JSON-RPC 2.0. Diagnostic output goes to stderr only.
