/**
 * edge_veda_add_capability tool
 *
 * Adds capability-specific code scaffolding to a Flutter project.
 * Creates a new screen file and provides the required model info.
 */

import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { writeFile, readFile } from "node:fs/promises";
import { join } from "node:path";
import { existsSync } from "node:fs";
import { execFileAsync } from "../utils.js";

// Code templates for each capability
const CAPABILITY_TEMPLATES: Record<
  string,
  { filename: string; code: string; models: string[]; extraDeps?: string[] }
> = {
  chat: {
    filename: "chat_screen.dart",
    models: ["llama-3.2-1b-instruct-q4"],
    code: `import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _edgeVeda = EdgeVeda();
  final _modelManager = ModelManager();
  ChatSession? _session;
  final _messages = <Map<String, String>>[];
  final _controller = TextEditingController();
  bool _isLoading = true;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final modelPath = await _modelManager.downloadModel(ModelRegistry.llama32_1b);
    final device = DeviceProfile.detect();
    final scored = ModelAdvisor.score(
      model: ModelRegistry.llama32_1b, device: device, useCase: UseCase.chat,
    );
    await _edgeVeda.init(EdgeVedaConfig(
      modelPath: modelPath,
      contextLength: scored.recommendedConfig.contextLength,
      numThreads: scored.recommendedConfig.numThreads,
      useGpu: true,
    ));
    _session = ChatSession(edgeVeda: _edgeVeda);
    setState(() { _isLoading = false; _status = 'Ready'; });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _session == null) return;
    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'assistant', 'content': ''});
      _isLoading = true;
    });

    await for (final chunk in _session!.sendStream(text)) {
      if (!chunk.isFinal) {
        setState(() {
          _messages.last['content'] = (_messages.last['content'] ?? '') + chunk.token;
        });
      }
    }
    setState(() { _isLoading = false; });
  }

  @override
  void dispose() {
    _edgeVeda.dispose();
    _modelManager.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          if (_status != 'Ready') Padding(
            padding: const EdgeInsets.all(16), child: Text(_status),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (ctx, i) {
                final msg = _messages[i];
                final isUser = msg['role'] == 'user';
                return ListTile(
                  title: Text(msg['content'] ?? ''),
                  leading: Icon(isUser ? Icons.person : Icons.smart_toy),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Type a message...'),
                  onSubmitted: (_) => _send(),
                )),
                IconButton(
                  onPressed: _isLoading ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
`,
  },

  vision: {
    filename: "vision_screen.dart",
    models: ["smolvlm2-500m-video-instruct-q8", "smolvlm2-500m-mmproj-f16"],
    extraDeps: ["image_picker: ^1.1.2", "image: ^4.0.0"],
    code: `import 'dart:io';
import 'dart:typed_data';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  final _edgeVeda = EdgeVeda();
  final _modelManager = ModelManager();
  String _output = 'Initializing vision...';
  String? _imagePath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final modelPath = await _modelManager.downloadModel(ModelRegistry.smolvlm2_500m);
    final mmprojPath = await _modelManager.downloadModel(ModelRegistry.smolvlm2_500m_mmproj);
    await _edgeVeda.initVision(VisionConfig(
      modelPath: modelPath, mmprojPath: mmprojPath,
    ));
    setState(() { _isLoading = false; _output = 'Ready! Pick an image.'; });
  }

  Future<void> _pickAndDescribe() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() { _imagePath = image.path; _isLoading = true; _output = 'Analyzing...'; });

    final bytes = await File(image.path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      setState(() { _output = 'Failed to decode selected image'; _isLoading = false; });
      return;
    }
    final rgb = Uint8List.fromList(decoded.getBytes(order: img.ChannelOrder.rgb));
    final result = await _edgeVeda.describeImage(
      rgb,
      width: decoded.width,
      height: decoded.height,
      prompt: 'Describe this image in detail.',
    );
    setState(() { _output = result; _isLoading = false; });
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
      appBar: AppBar(title: const Text('Vision')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_imagePath != null) Image.file(File(_imagePath!), height: 200),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: Text(_output))),
            ElevatedButton(
              onPressed: _isLoading ? null : _pickAndDescribe,
              child: Text(_isLoading ? 'Working...' : 'Pick Image'),
            ),
          ],
        ),
      ),
    );
  }
}
`,
  },

  stt: {
    filename: "stt_screen.dart",
    models: ["whisper-base-en"],
    extraDeps: [],
    code: `import 'dart:async';
import 'dart:typed_data';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

class SttScreen extends StatefulWidget {
  const SttScreen({super.key});

  @override
  State<SttScreen> createState() => _SttScreenState();
}

class _SttScreenState extends State<SttScreen> {
  final _modelManager = ModelManager();
  String? _modelPath;
  WhisperSession? _whisper;
  StreamSubscription<WhisperSegment>? _segmentSubscription;
  StreamSubscription<Float32List>? _audioSubscription;
  String _transcript = 'Tap microphone to start...';
  bool _isRecording = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    _modelPath = await _modelManager.downloadModel(ModelRegistry.whisperBaseEn);
    setState(() { _isLoading = false; });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      await _whisper?.flush();
      await _whisper?.stop();
      await _segmentSubscription?.cancel();
      _segmentSubscription = null;
      setState(() { _isRecording = false; });
    } else {
      if (_modelPath == null) return;
      final granted = await WhisperSession.requestMicrophonePermission();
      if (!granted) {
        setState(() { _transcript = 'Microphone permission denied'; });
        return;
      }
      _whisper = WhisperSession(modelPath: _modelPath!);
      await _whisper!.start();
      await _segmentSubscription?.cancel();
      _segmentSubscription = _whisper!.onSegment.listen((segment) {
        setState(() { _transcript = _whisper!.transcript; });
      });
      _audioSubscription = WhisperSession.microphone().listen((samples) {
        _whisper?.feedAudio(samples);
      });
      setState(() { _isRecording = true; _transcript = ''; });
    }
  }

  @override
  void dispose() {
    _audioSubscription?.cancel();
    _segmentSubscription?.cancel();
    _whisper?.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speech to Text')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(_transcript, style: const TextStyle(fontSize: 18)),
              ),
            ),
            FloatingActionButton(
              onPressed: _isLoading ? null : _toggleRecording,
              child: Icon(_isRecording ? Icons.stop : Icons.mic),
            ),
          ],
        ),
      ),
    );
  }
}
`,
  },

  tts: {
    filename: "tts_screen.dart",
    models: [],
    code: `import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final _tts = TtsService();
  final _controller = TextEditingController(
    text: 'Hello! I am running entirely on your device with no cloud connection.',
  );
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _speak() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _isSpeaking = true; });
    await _tts.speak(text);
    setState(() { _isSpeaking = false; });
  }

  void _stop() {
    _tts.stop();
    setState(() { _isSpeaking = false; });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Text to Speech')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter text to speak...',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isSpeaking ? null : _speak,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Speak'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isSpeaking ? _stop : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'TTS uses iOS AVSpeechSynthesizer via platform channel.\\n'
              'No model download needed -- zero binary size increase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
`,
  },

  image: {
    filename: "image_screen.dart",
    models: ["sd-v2-1-turbo-q8"],
    code: `import 'dart:typed_data';
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

class ImageScreen extends StatefulWidget {
  const ImageScreen({super.key});

  @override
  State<ImageScreen> createState() => _ImageScreenState();
}

class _ImageScreenState extends State<ImageScreen> {
  final _edgeVeda = EdgeVeda();
  final _modelManager = ModelManager();
  final _controller = TextEditingController(text: 'A serene mountain lake at sunset');
  Uint8List? _result;
  String _status = 'Initializing...';
  bool _isLoading = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final modelPath = await _modelManager.downloadModel(ModelRegistry.sdV21Turbo);
    await _edgeVeda.initImageGeneration(modelPath: modelPath);
    setState(() { _isLoading = false; _status = 'Ready'; });
  }

  Future<void> _generate() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty) return;
    setState(() { _isLoading = true; _progress = 0; _status = 'Generating...'; });

    final result = await _edgeVeda.generateImage(
      prompt,
      onProgress: (p) {
        setState(() { _progress = p.progress; });
      },
    );
    setState(() { _result = result; _isLoading = false; _status = 'Done'; });
  }

  @override
  void dispose() {
    _edgeVeda.dispose();
    _modelManager.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image Generation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Describe the image...',
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoading) LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Expanded(
              child: _result != null
                  ? Image.memory(_result!, fit: BoxFit.contain)
                  : Center(child: Text(_status)),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : _generate,
              child: Text(_isLoading ? 'Generating...' : 'Generate Image'),
            ),
          ],
        ),
      ),
    );
  }
}
`,
  },

  rag: {
    filename: "rag_screen.dart",
    models: ["all-minilm-l6-v2-f16", "llama-3.2-1b-instruct-q4"],
    extraDeps: ["file_picker: ^8.0.0"],
    code: `import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class RagScreen extends StatefulWidget {
  const RagScreen({super.key});

  @override
  State<RagScreen> createState() => _RagScreenState();
}

class _RagScreenState extends State<RagScreen> {
  final _generator = EdgeVeda();
  final _embedder = EdgeVeda();
  final _modelManager = ModelManager();
  RagPipeline? _rag;
  final _controller = TextEditingController();
  String _output = 'Load a document first...';
  bool _isLoading = true;
  bool _hasDocument = false;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    // Download both models
    final embedPath = await _modelManager.downloadModel(ModelRegistry.allMiniLmL6V2);
    final llmPath = await _modelManager.downloadModel(ModelRegistry.llama32_1b);

    // Initialize separate embedder and generator models
    await _embedder.init(EdgeVedaConfig(modelPath: embedPath, useGpu: true));
    await _generator.init(EdgeVedaConfig(modelPath: llmPath, useGpu: true));

    // Create RAG pipeline
    _rag = RagPipeline.withModels(
      embedder: _embedder,
      generator: _generator,
      index: VectorIndex(dimensions: 384),
      ftsIndex: FtsIndex(),
    );

    setState(() { _isLoading = false; _output = 'Ready! Pick a text document.'; });
  }

  Future<void> _loadDocument() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null) return;

    setState(() { _isLoading = true; _output = 'Indexing document...'; });
    final text = await File(result.files.single.path!).readAsString();

    await _rag!.addDocument(
      result.files.single.name,
      text,
      metadata: {'source': result.files.single.name},
    );
    setState(() { _isLoading = false; _hasDocument = true; _output = 'Document indexed. Ask a question!'; });
  }

  Future<void> _query() async {
    final q = _controller.text.trim();
    if (q.isEmpty || _rag == null) return;
    _controller.clear();
    setState(() { _isLoading = true; _output = ''; });

    await for (final chunk in _rag!.queryStream(q)) {
      if (!chunk.isFinal) {
        setState(() { _output += chunk.token; });
      }
    }
    setState(() { _isLoading = false; });
  }

  @override
  void dispose() {
    _generator.dispose();
    _embedder.dispose();
    _modelManager.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RAG Q&A')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _loadDocument,
              child: const Text('Load Document'),
            ),
            const SizedBox(height: 16),
            Expanded(child: SingleChildScrollView(child: Text(_output))),
            if (_hasDocument) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Ask about the document...'),
                    onSubmitted: (_) => _query(),
                  )),
                  IconButton(onPressed: _isLoading ? null : _query, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
`,
  },
};

export function registerAddCapability(server: McpServer): void {
  server.tool(
    "edge_veda_add_capability",
    "Add a capability (chat, vision, stt, tts, image, rag) with code scaffolding to a Flutter project",
    {
      capability: z
        .enum(["chat", "vision", "stt", "tts", "image", "rag"])
        .describe("The capability to add"),
      project_path: z
        .string()
        .describe("Path to the Flutter project"),
    },
    async ({ capability, project_path }) => {
      const template = CAPABILITY_TEMPLATES[capability];
      if (!template) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Unknown capability: ${capability}. Available: chat, vision, stt, tts, image, rag`,
            },
          ],
        };
      }

      const filePath = join(project_path, "lib", template.filename);
      const steps: string[] = [];

      // Check if file already exists (idempotency warning)
      if (existsSync(filePath)) {
        steps.push(`Warning: lib/${template.filename} already exists -- overwriting`);
      }

      // Write the screen file
      try {
        await writeFile(filePath, template.code);
        steps.push(`Created lib/${template.filename}`);
      } catch (e) {
        return {
          content: [
            {
              type: "text" as const,
              text: `Failed to write ${filePath}: ${e}`,
            },
          ],
        };
      }

      // Add extra dependencies if needed
      if (template.extraDeps && template.extraDeps.length > 0) {
        try {
          const pubspecPath = join(project_path, "pubspec.yaml");
          let pubspec = await readFile(pubspecPath, "utf-8");

          for (const dep of template.extraDeps) {
            if (!pubspec.includes(dep)) {
              pubspec = pubspec.replace(
                /(edge_veda: \^[\d.]+\n)/,
                `$1  ${dep}\n`,
              );
            }
          }
          await writeFile(pubspecPath, pubspec);
          steps.push(`Added dependencies: ${template.extraDeps.join(", ")}`);
        } catch (e) {
          steps.push(
            `Warning: Could not update pubspec.yaml for extra deps: ${e}`,
          );
        }
      }

      // Run flutter pub get to resolve dependencies
      const pubGetResult = await execFileAsync("flutter", ["pub", "get"], { cwd: project_path });
      if (pubGetResult.exitCode === 0) {
        steps.push("flutter pub get succeeded");
      } else {
        steps.push(`Warning: flutter pub get failed: ${pubGetResult.stderr}`);
      }

      // Build response
      const lines = [
        `# Added Capability: ${capability}\n`,
        `File: lib/${template.filename}`,
        "",
        "## Steps Completed\n",
        ...steps.map((s) => `- ${s}`),
        "",
      ];

      if (template.models.length > 0) {
        lines.push("## Required Models\n");
        lines.push(
          "Download these models before running:\n",
        );
        for (const modelId of template.models) {
          lines.push(`- ${modelId}`);
        }
        lines.push(
          "",
          "Use `edge_veda_download_model` to download each model.",
        );
      } else {
        lines.push(
          "No model download needed for this capability.",
        );
      }

      lines.push(
        "",
        "## Wiring\n",
        `Add this import to lib/main.dart:`,
        "```dart",
        `import '${template.filename}';`,
        "```",
        "",
        `Then add the screen to your app's navigation (e.g., as a tab or route).`,
      );

      return {
        content: [{ type: "text" as const, text: lines.join("\n") }],
      };
    },
  );
}
