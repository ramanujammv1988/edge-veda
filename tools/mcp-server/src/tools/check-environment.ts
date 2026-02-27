/**
 * edge_veda_check_environment tool
 *
 * Verifies that all prerequisites for Edge Veda development are installed:
 * Flutter SDK, Xcode, CocoaPods, and connected iOS device.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { exec } from "../utils.js";
import { getConnectedIOSDevice } from "../device-profile.js";

interface CheckResult {
  name: string;
  status: "pass" | "fail" | "warn";
  version: string;
  detail: string;
}

export function registerCheckEnvironment(server: McpServer): void {
  server.tool(
    "edge_veda_check_environment",
    "Check development environment for Edge Veda: Flutter, Xcode, CocoaPods, iOS device",
    {},
    async () => {
      const checks: CheckResult[] = [];

      // Run independent checks in parallel
      const [flutter, xcode, pods, device] = await Promise.all([
        exec("flutter --version"),
        exec("xcode-select -p"),
        exec("pod --version"),
        getConnectedIOSDevice(),
      ]);

      // Flutter
      if (flutter.exitCode === 0) {
        const versionMatch = flutter.stdout.match(/Flutter\s+([\d.]+)/);
        checks.push({
          name: "Flutter SDK",
          status: "pass",
          version: versionMatch ? versionMatch[1] : "installed",
          detail: "Flutter is installed and on PATH",
        });
      } else {
        checks.push({
          name: "Flutter SDK",
          status: "fail",
          version: "not found",
          detail:
            "Flutter not found. Install from https://docs.flutter.dev/get-started/install",
        });
      }

      // Xcode -- xcodebuild needs xcode-select to have succeeded
      if (xcode.exitCode === 0) {
        const xcodeVersion = await exec("xcodebuild -version");
        const verMatch = xcodeVersion.stdout.match(/Xcode\s+([\d.]+)/);
        checks.push({
          name: "Xcode",
          status: "pass",
          version: verMatch ? verMatch[1] : "installed",
          detail: `Path: ${xcode.stdout.trim()}`,
        });
      } else {
        checks.push({
          name: "Xcode",
          status: "fail",
          version: "not found",
          detail:
            "Xcode not installed. Install from the Mac App Store or run: xcode-select --install",
        });
      }

      // CocoaPods
      if (pods.exitCode === 0) {
        checks.push({
          name: "CocoaPods",
          status: "pass",
          version: pods.stdout.trim(),
          detail: "CocoaPods is installed",
        });
      } else {
        checks.push({
          name: "CocoaPods",
          status: "fail",
          version: "not found",
          detail:
            "CocoaPods not found. Install with: gem install cocoapods",
        });
      }

      // Connected iOS device
      if (device) {
        checks.push({
          name: "iOS Device",
          status: "pass",
          version: `iOS ${device.osVersion}`,
          detail: `${device.name} (${device.udid})`,
        });
      } else {
        checks.push({
          name: "iOS Device",
          status: "warn",
          version: "none",
          detail:
            "No physical iOS device connected. You can still use the iOS Simulator (CPU-only, slower).",
        });
      }

      // Format report
      const allPass = checks.every((c) => c.status !== "fail");
      const lines = [
        "# Edge Veda Environment Check\n",
        ...checks.map((c) => {
          const icon =
            c.status === "pass"
              ? "[PASS]"
              : c.status === "warn"
                ? "[WARN]"
                : "[FAIL]";
          return `${icon} ${c.name}: ${c.version}\n    ${c.detail}`;
        }),
        "",
        allPass
          ? "Environment is ready for Edge Veda development."
          : "Some prerequisites are missing. Fix the FAIL items above before continuing.",
      ];

      return {
        content: [{ type: "text" as const, text: lines.join("\n") }],
      };
    },
  );
}
