/**
 * edge_veda_create_project tool
 *
 * Scaffolds a working Flutter project with edge_veda dependency,
 * correct Podfile settings, and a boilerplate main.dart.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { execFileAsync, validateProjectName } from "../utils.js";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

/** Map model_id to Dart registry constant and use case */
const MODEL_ID_TO_DART: Record<string, { registry: string; useCase: string }> = {
  'llama-3.2-1b-instruct-q4': { registry: 'ModelRegistry.llama32_1b', useCase: 'UseCase.chat' },
  'phi-3.5-mini-instruct-q4': { registry: 'ModelRegistry.phi35_mini', useCase: 'UseCase.chat' },
  'gemma-2-2b-instruct-q4': { registry: 'ModelRegistry.gemma2_2b', useCase: 'UseCase.chat' },
  'qwen3-0.6b-q4': { registry: 'ModelRegistry.qwen3_06b', useCase: 'UseCase.chat' },
  'tinyllama-1.1b-chat-q4': { registry: 'ModelRegistry.tinyLlama', useCase: 'UseCase.chat' },
};

/** Generate boilerplate main.dart with the specified model registry constant and use case */
function getBoilerplateMain(registryConst: string, useCase: string): string {
  return `import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Edge Veda Quickstart',
      home: QuickstartScreen(),
    );
  }
}

class QuickstartScreen extends StatefulWidget {
  const QuickstartScreen({super.key});

  @override
  State<QuickstartScreen> createState() => _QuickstartScreenState();
}

class _QuickstartScreenState extends State<QuickstartScreen> {
  final _edgeVeda = EdgeVeda();
  final _modelManager = ModelManager();
  String _output = 'Initializing...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      // 1. Download model (returns immediately if already cached)
      setState(() { _output = 'Downloading model...'; });
      final modelPath = await _modelManager.downloadModel(
        ${registryConst},
      );
      if (!mounted) return;

      // 2. Get device-optimized config
      final device = DeviceProfile.detect();
      final scored = ModelAdvisor.score(
        model: ${registryConst},
        device: device,
        useCase: ${useCase},
      );
      final config = EdgeVedaConfig(
        modelPath: modelPath,
        contextLength: scored.recommendedConfig.contextLength,
        numThreads: scored.recommendedConfig.numThreads,
        useGpu: true,
      );

      // 3. Initialize the inference engine
      setState(() { _output = 'Loading model...'; });
      await _edgeVeda.init(config);
      if (!mounted) return;
      setState(() { _isLoading = false; _output = 'Ready! Tap Generate.'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _output = 'Error: \$e'; _isLoading = false; });
    }
  }

  Future<void> _generate() async {
    setState(() { _output = ''; _isLoading = true; });

    try {
      await for (final chunk in _edgeVeda.generateStream(
        'Explain what on-device AI means in two sentences.',
      )) {
        if (!chunk.isFinal) {
          setState(() { _output += chunk.token; });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _output = 'Generation error: \$e'; });
    }

    if (!mounted) return;
    setState(() { _isLoading = false; });
  }

  @override
  void dispose() {
    _edgeVeda.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edge Veda Quickstart')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _output,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _generate,
              child: Text(_isLoading ? 'Working...' : 'Generate'),
            ),
          ],
        ),
      ),
    );
  }
}
`;
}

export function registerCreateProject(server: McpServer): void {
  server.tool(
    "edge_veda_create_project",
    "Create a new Flutter project with Edge Veda SDK configured and ready to run",
    {
      project_name: z
        .string()
        .describe("Name for the Flutter project (lowercase_with_underscores)"),
      path: z
        .string()
        .optional()
        .describe("Directory to create project in (defaults to cwd)"),
      model_id: z
        .string()
        .optional()
        .describe("Model ID (defaults to llama-3.2-1b-instruct-q4)"),
    },
    async ({ project_name, path: targetPath, model_id }) => {
      // Validate project name to prevent command injection
      try {
        validateProjectName(project_name);
      } catch (e) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Invalid project name: ${(e as Error).message}`,
            },
          ],
        };
      }

      // Resolve model_id to Dart registry constant
      const resolvedModelId = model_id ?? "llama-3.2-1b-instruct-q4";
      const dartModel = MODEL_ID_TO_DART[resolvedModelId];
      if (!dartModel) {
        const validIds = Object.keys(MODEL_ID_TO_DART).join(", ");
        return {
          content: [
            {
              type: "text" as const,
              text: `Unknown model_id: ${resolvedModelId}\n\nValid model IDs for create_project: ${validIds}`,
            },
          ],
        };
      }

      const cwd = targetPath ?? process.cwd();
      const projectDir = join(cwd, project_name);
      const steps: string[] = [];

      // 1. Create Flutter project (execFileAsync -- no shell interpolation)
      steps.push("Creating Flutter project...");
      const create = await execFileAsync("flutter", ["create", project_name], { cwd });
      if (create.exitCode !== 0 && !create.stderr.includes("already exists")) {
        // Try again in cwd (same call, cwd option replaces cd)
        const create2 = await execFileAsync("flutter", ["create", project_name], { cwd });
        if (create2.exitCode !== 0) {
          return {
            content: [
              {
                type: "text" as const,
                text: `Failed to create Flutter project:\n${create2.stderr}\n${create2.stdout}`,
              },
            ],
          };
        }
      }
      steps.push("Flutter project created.");

      // 2. Patch pubspec.yaml -- add edge_veda dependency
      try {
        const pubspecPath = join(projectDir, "pubspec.yaml");
        let pubspec = await readFile(pubspecPath, "utf-8");

        if (!pubspec.includes("edge_veda")) {
          // Insert after the flutter sdk dependency
          pubspec = pubspec.replace(
            /(\s+flutter:\n\s+sdk: flutter\n)/,
            `$1  edge_veda: ^2.4.2\n`,
          );
          await writeFile(pubspecPath, pubspec);
          steps.push("Added edge_veda: ^2.4.2 to pubspec.yaml");
        }
      } catch (e) {
        steps.push(`Warning: Could not patch pubspec.yaml: ${e}`);
      }

      // 3. Run flutter pub get
      const pubGet = await execFileAsync("flutter", ["pub", "get"], { cwd: projectDir });
      if (pubGet.exitCode === 0) {
        steps.push("flutter pub get succeeded");
      } else {
        steps.push(`Warning: flutter pub get failed: ${pubGet.stderr}`);
      }

      // 4. Patch iOS Podfile (AFTER pub get so Podfile exists from flutter create)
      try {
        const podfilePath = join(projectDir, "ios", "Podfile");
        let podfile = await readFile(podfilePath, "utf-8");

        // Uncomment and set platform version to 13.0 (SDK minimum)
        podfile = podfile.replace(
          /# platform :ios, '[\d.]+'/,
          "platform :ios, '13.0'",
        );
        podfile = podfile.replace(
          /platform :ios, '[\d.]+'/,
          "platform :ios, '13.0'",
        );

        // Switch from use_frameworks! to use_modular_headers! for FFI compatibility
        if (/use_frameworks!/.test(podfile)) {
          podfile = podfile.replace(/use_frameworks!/, "use_modular_headers!");
          steps.push("Replaced use_frameworks! with use_modular_headers! in Podfile");
        } else if (!podfile.includes("use_modular_headers!")) {
          const before = podfile;
          podfile = podfile.replace(
            /(target\s+'Runner'\s+do\n)/,
            "$1  use_modular_headers!\n",
          );
          if (podfile !== before) {
            steps.push("Inserted use_modular_headers! in Podfile (use_frameworks! not found)");
          } else {
            steps.push("Warning: Could not find insertion point for use_modular_headers! in Podfile — add it manually");
          }
        } else {
          steps.push("Podfile already has use_modular_headers!");
        }

        await writeFile(podfilePath, podfile);
        steps.push("Set iOS 13.0 in Podfile");
      } catch (e) {
        steps.push(`Warning: Could not patch Podfile: ${e}`);
      }

      // 5. Run pod install
      const podInstall = await execFileAsync("pod", ["install"], {
        cwd: join(projectDir, "ios"),
      });
      if (podInstall.exitCode === 0) {
        steps.push("pod install succeeded");
      } else {
        steps.push(
          `Warning: pod install failed (may need to run manually): ${podInstall.stderr.slice(0, 500)}`,
        );
      }

      // 6. Write boilerplate main.dart
      try {
        const mainPath = join(projectDir, "lib", "main.dart");
        await writeFile(mainPath, getBoilerplateMain(dartModel.registry, dartModel.useCase));
        steps.push("Wrote boilerplate lib/main.dart with Edge Veda quickstart");
      } catch (e) {
        steps.push(`Warning: Could not write main.dart: ${e}`);
      }

      const summary = [
        `# Project Created: ${project_name}\n`,
        `Path: ${projectDir}`,
        `Model: ${resolvedModelId}\n`,
        "## Steps Completed\n",
        ...steps.map((s) => `- ${s}`),
        "",
        "## Next Steps\n",
        "1. Use `edge_veda_list_models` to see available models",
        "2. Use `edge_veda_download_model` to download a model",
        "3. Use `edge_veda_run` to build and deploy to your device",
        "",
        `The boilerplate main.dart auto-downloads ${resolvedModelId} on first launch.`,
      ];

      return {
        content: [{ type: "text" as const, text: summary.join("\n") }],
      };
    },
  );
}
