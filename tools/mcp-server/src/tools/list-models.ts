/**
 * edge_veda_list_models tool
 *
 * Lists available models with device-aware recommendations.
 * Filters by use case and shows memory fit status per model.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import {
  MODEL_REGISTRY,
  getModelsByCapability,
  getRecommendedModel,
  type ModelInfo,
} from "../model-registry.js";
import {
  detectDeviceTier,
  estimateMemoryMB,
  modelFitsDevice,
  formatSize,
} from "../device-profile.js";

export function registerListModels(server: McpServer): void {
  server.tool(
    "edge_veda_list_models",
    "List available AI models with device-aware recommendations and memory estimates",
    {
      use_case: z
        .enum([
          "chat",
          "vision",
          "stt",
          "tts",
          "image",
          "embedding",
          "tool-calling",
        ])
        .optional()
        .describe(
          "Filter models by use case (chat, vision, stt, tts, image, embedding, tool-calling)",
        ),
      show_all: z
        .boolean()
        .optional()
        .describe("Show all models including projectors and large desktop models"),
    },
    async ({ use_case, show_all }) => {
      const { tier, ramGB, chip } = await detectDeviceTier();

      // Map use_case to capability filter
      const capabilityMap: Record<string, string> = {
        chat: "chat",
        vision: "vision",
        stt: "stt",
        tts: "stt", // TTS uses platform channel, no model; show STT info
        image: "imageGeneration",
        embedding: "embedding",
        "tool-calling": "tool-calling",
      };

      let models: ModelInfo[];
      if (use_case) {
        const cap = capabilityMap[use_case];
        if (cap) {
          models = getModelsByCapability(cap);
        } else {
          models = [...MODEL_REGISTRY];
        }
      } else {
        models = [...MODEL_REGISTRY];
      }

      // Filter out projectors unless show_all
      if (!show_all) {
        models = models.filter(
          (m) => !m.capabilities.includes("vision-projector"),
        );
      }

      // Get recommendation
      const recommended = use_case
        ? getRecommendedModel(use_case)
        : getRecommendedModel("chat");

      // Build table
      const lines: string[] = [
        `# Edge Veda Model Registry\n`,
        `Developer machine: ${chip}, ${ramGB}GB RAM (tier: ${tier})\n`,
      ];

      if (use_case === "tts") {
        lines.push(
          "Note: TTS uses iOS AVSpeechSynthesizer (platform channel). No model download needed.\n",
        );
      }

      // Table header
      lines.push(
        "| Model | Size | Est. Memory | Fits | Capabilities | Recommended |",
      );
      lines.push(
        "|-------|------|-------------|------|-------------|-------------|",
      );

      for (const model of models) {
        const memMB = estimateMemoryMB(model);
        const fits = modelFitsDevice(model, tier);
        const isRecommended = model.id === recommended.id;
        const capsStr = model.capabilities.join(", ");

        lines.push(
          `| ${model.name} | ${formatSize(model.sizeBytes)} | ${memMB} MB | ${fits ? "Yes" : "No"} | ${capsStr} | ${isRecommended ? "** YES **" : ""} |`,
        );
      }

      if (recommended) {
        lines.push(
          `\nRecommended model: **${recommended.name}** (${recommended.id})`,
        );
        lines.push(`Size: ${formatSize(recommended.sizeBytes)}`);
        lines.push(
          `Estimated memory: ${estimateMemoryMB(recommended)} MB`,
        );
      }

      return {
        content: [{ type: "text" as const, text: lines.join("\n") }],
      };
    },
  );
}
