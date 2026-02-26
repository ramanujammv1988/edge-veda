/**
 * edge_veda_create_project tool
 *
 * Scaffolds a working Flutter project with edge_veda dependency,
 * correct Podfile settings, and a boilerplate main.dart.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { exec } from "../utils.js";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const BOILERPLATE_MAIN = `import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Edge Veda Quickstart',
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
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
        ModelRegistry.llama32_1b,
      );

      // 2. Get device-optimized config
      final device = DeviceProfile.detect();
      final scored = ModelAdvisor.score(
        model: ModelRegistry.llama32_1b,
        device: device,
        useCase: UseCase.chat,
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
      setState(() { _isLoading = false; _output = 'Ready! Tap Generate.'; });
    } catch (e) {
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
      setState(() { _output = 'Generation error: \$e'; });
    }

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
    },
    async ({ project_name, path: targetPath }) => {
      const cwd = targetPath ?? process.cwd();
      const projectDir = join(cwd, project_name);
      const steps: string[] = [];

      // 1. Create Flutter project
      steps.push("Creating Flutter project...");
      const create = await exec(`flutter create ${project_name}`, );
      if (create.exitCode !== 0 && !create.stderr.includes("already exists")) {
        // Try running in cwd
        const create2 = await exec(`cd "${cwd}" && flutter create ${project_name}`);
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

      // 3. Patch iOS Podfile
      try {
        const podfilePath = join(projectDir, "ios", "Podfile");
        let podfile = await readFile(podfilePath, "utf-8");

        // Uncomment and set platform version
        podfile = podfile.replace(
          /# platform :ios, '[\d.]+'/,
          "platform :ios, '13.0'",
        );
        podfile = podfile.replace(
          /platform :ios, '[\d.]+'/,
          "platform :ios, '13.0'",
        );
        await writeFile(podfilePath, podfile);
        steps.push("Set iOS deployment target to 13.0 in Podfile");
      } catch (e) {
        steps.push(`Warning: Could not patch Podfile: ${e}`);
      }

      // 4. Run flutter pub get
      const pubGet = await exec(`cd "${projectDir}" && flutter pub get`);
      if (pubGet.exitCode === 0) {
        steps.push("flutter pub get succeeded");
      } else {
        steps.push(`Warning: flutter pub get failed: ${pubGet.stderr}`);
      }

      // 5. Run pod install
      const podInstall = await exec(
        `cd "${join(projectDir, "ios")}" && pod install`,
      );
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
        await writeFile(mainPath, BOILERPLATE_MAIN);
        steps.push("Wrote boilerplate lib/main.dart with Edge Veda quickstart");
      } catch (e) {
        steps.push(`Warning: Could not write main.dart: ${e}`);
      }

      const summary = [
        `# Project Created: ${project_name}\n`,
        `Path: ${projectDir}\n`,
        "## Steps Completed\n",
        ...steps.map((s) => `- ${s}`),
        "",
        "## Next Steps\n",
        "1. Use `edge_veda_list_models` to see available models",
        "2. Use `edge_veda_download_model` to download a model",
        "3. Use `edge_veda_run` to build and deploy to your device",
        "",
        "The boilerplate main.dart auto-downloads Llama 3.2 1B on first launch.",
      ];

      return {
        content: [{ type: "text" as const, text: summary.join("\n") }],
      };
    },
  );
}
