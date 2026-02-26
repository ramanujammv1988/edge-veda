/**
 * edge_veda_download_model tool
 *
 * Downloads a model GGUF/bin file to a local path for import into a
 * Flutter project. Uses curl for direct download with progress.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { exec } from "../utils.js";
import { getModelById, MODEL_REGISTRY } from "../model-registry.js";
import { formatSize } from "../device-profile.js";
import { existsSync } from "node:fs";
import { join } from "node:path";

export function registerDownloadModel(server: McpServer): void {
  server.tool(
    "edge_veda_download_model",
    "Download an AI model file for use in an Edge Veda Flutter project",
    {
      model_id: z
        .string()
        .describe(
          "Model ID from list_models (e.g. llama-3.2-1b-instruct-q4)",
        ),
      project_path: z
        .string()
        .describe("Path to the Flutter project"),
    },
    async ({ model_id, project_path }) => {
      const model = getModelById(model_id);
      if (!model) {
        const available = MODEL_REGISTRY.map((m) => m.id).join("\n  ");
        return {
          content: [
            {
              type: "text" as const,
              text: `Model not found: ${model_id}\n\nAvailable models:\n  ${available}`,
            },
          ],
        };
      }

      const ext = model_id.startsWith("whisper-") ? "bin" : "gguf";
      const filename = `${model_id}.${ext}`;
      const downloadPath = join("/tmp", filename);

      // Check if already downloaded
      if (existsSync(downloadPath)) {
        return {
          content: [
            {
              type: "text" as const,
              text: [
                `# Model Already Downloaded\n`,
                `Model: ${model.name}`,
                `Path: ${downloadPath}`,
                `Size: ${formatSize(model.sizeBytes)}`,
                "",
                "The model file already exists at the path above.",
                "",
                "## Usage in your app\n",
                "The boilerplate main.dart auto-downloads models on first launch.",
                "Alternatively, use `importModel()` to load from this path:",
                "```dart",
                `final path = await modelManager.importModel(`,
                `  ModelRegistry.getModelById('${model_id}')!,`,
                `  sourcePath: '${downloadPath}',`,
                `);`,
                "```",
              ].join("\n"),
            },
          ],
        };
      }

      // Download using curl with progress
      const curlCmd = `curl -L --progress-bar -o "${downloadPath}" "${model.downloadUrl}"`;
      const result = await exec(curlCmd);

      if (result.exitCode !== 0) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Download failed:\n${result.stderr}\n\nYou can also download manually:\n  curl -L -o "${downloadPath}" "${model.downloadUrl}"`,
            },
          ],
        };
      }

      // Verify file exists
      if (!existsSync(downloadPath)) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Download appeared to succeed but file not found at ${downloadPath}.\nTry downloading manually.`,
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text" as const,
            text: [
              `# Model Downloaded Successfully\n`,
              `Model: ${model.name}`,
              `Path: ${downloadPath}`,
              `Size: ${formatSize(model.sizeBytes)}`,
              "",
              "## Next Steps\n",
              "The boilerplate main.dart auto-downloads models on first launch.",
              "To use this pre-downloaded file instead, call `importModel()`:",
              "```dart",
              `final path = await modelManager.importModel(`,
              `  ModelRegistry.getModelById('${model_id}')!,`,
              `  sourcePath: '${downloadPath}',`,
              `);`,
              "```",
              "",
              `Or run the app with: edge_veda_run --project_path "${project_path}"`,
            ].join("\n"),
          },
        ],
      };
    },
  );
}
