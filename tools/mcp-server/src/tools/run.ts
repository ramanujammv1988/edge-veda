/**
 * edge_veda_run tool
 *
 * Builds and deploys a Flutter project to a connected iOS device.
 * Defaults to release mode for optimal inference performance.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { execFileAsync, validateDeviceId, validateProjectPath } from "../utils.js";
import { getConnectedIOSDevice } from "../device-profile.js";

export function registerRun(server: McpServer): void {
  server.tool(
    "edge_veda_run",
    "Build and deploy a Flutter project to a connected iOS device",
    {
      project_path: z.string().describe("Path to the Flutter project"),
      mode: z
        .enum(["debug", "profile", "release"])
        .optional()
        .default("release")
        .describe("Build mode (debug, profile, release). Defaults to release for best inference speed."),
      device_id: z
        .string()
        .optional()
        .describe("Device UDID (auto-detects if not provided)"),
    },
    async ({ project_path, mode, device_id }) => {
      // Validate inputs to prevent command injection
      try {
        validateProjectPath(project_path);
        if (device_id) {
          validateDeviceId(device_id);
        }
      } catch (e) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Invalid input: ${(e as Error).message}`,
            },
          ],
        };
      }

      // Resolve device
      let deviceId: string | undefined;
      if (device_id) {
        deviceId = device_id;
      } else {
        const device = await getConnectedIOSDevice();
        if (device) {
          deviceId = device.udid;
        }
        // If no device, flutter run will pick the default (simulator)
      }

      const modeArg = mode ? `--${mode}` : "--release";
      const args = ["run", modeArg];
      if (deviceId) {
        args.push("-d", deviceId);
      }

      const displayCmd = `flutter ${args.join(" ")}`;

      const lines: string[] = [
        `# Building and Deploying\n`,
        `Project: ${project_path}`,
        `Mode: ${mode || "release"}`,
        `Device: ${device_id || "auto-detect"}`,
        `Command: \`${displayCmd}\`\n`,
        "Building...\n",
      ];

      // Run with a generous timeout (Flutter builds can take a while)
      const result = await execFileAsync("flutter", args, { cwd: project_path });

      if (result.exitCode === 0) {
        lines.push("## Build Succeeded\n");
        // Extract relevant output lines
        const outputLines = result.stdout.split("\n");
        const relevantLines = outputLines.filter(
          (l) =>
            l.includes("Installing") ||
            l.includes("Launching") ||
            l.includes("Successfully") ||
            l.includes("Running") ||
            l.includes("Syncing"),
        );
        if (relevantLines.length > 0) {
          lines.push(...relevantLines);
        } else {
          lines.push("App deployed to device.");
        }
      } else {
        lines.push("## Build Failed\n");

        // Extract error snippets
        const stderr = result.stderr || result.stdout;
        const errorLines = stderr.split("\n").filter(
          (l: string) =>
            l.includes("error:") ||
            l.includes("Error:") ||
            l.includes("FAILURE") ||
            l.includes("Could not"),
        );

        if (errorLines.length > 0) {
          lines.push("### Errors\n");
          lines.push("```");
          lines.push(...errorLines.slice(0, 20));
          lines.push("```");
        } else {
          lines.push("```");
          lines.push(stderr.slice(0, 2000));
          lines.push("```");
        }

        lines.push(
          "",
          "### Common Fixes\n",
          "- Signing: Open ios/Runner.xcworkspace in Xcode, set development team",
          "- Pods: Run `cd ios && pod install`",
          "- Clean build: Run `flutter clean && flutter pub get`",
        );
      }

      return {
        content: [{ type: "text" as const, text: lines.join("\n") }],
      };
    },
  );
}
