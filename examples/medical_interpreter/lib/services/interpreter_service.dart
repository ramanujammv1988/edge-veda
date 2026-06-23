import 'package:edge_veda/edge_veda.dart';

import '../models/conversation.dart';

/// Regex to strip leaked special tokens from model output.
/// Matches both Llama-style <|...|> and Gemma-style <start_of_turn>, <end_of_turn>, etc.
final _specialTokenPattern = RegExp(r'<\|[^>]*\|>|<(start_of_turn|end_of_turn|bos|eos|pad|unk)[^>]*>');

/// Core translation service wrapping MedGemma for medical-aware interpretation.
///
/// Uses lazy initialization: MedGemma is only loaded on the first translate()
/// call, not at app startup. This avoids OOM when Whisper is also loaded
/// (combined GPU memory would exceed iOS Jetsam limits).
class InterpreterService {
  final ModelManager _modelManager = ModelManager();

  EdgeVeda? _generator;
  String? _modelPath;
  bool _isDownloaded = false;

  /// Whether the model file is downloaded (not necessarily loaded into GPU).
  bool get isDownloaded => _isDownloaded;

  /// Whether the generator model is loaded in GPU memory and ready.
  bool get isReady => _generator != null;

  /// Download MedGemma model file only (no GPU init).
  ///
  /// Call this at app startup to ensure the model is cached on disk.
  /// The heavy GPU initialization is deferred to the first translate() call.
  Future<void> ensureDownloaded({
    required void Function(String status) onStatus,
    required void Function(double progress) onProgress,
  }) async {
    onStatus('Downloading Gemma 2 2B (1.6 GB)...');
    _modelPath = await _ensureModel(
      ModelRegistry.medgemma15_4b,
      onProgress,
    );
    _isDownloaded = true;
    onStatus('Model downloaded');
  }

  /// Load MedGemma into GPU memory. Called lazily on first translate().
  Future<void> _loadModel() async {
    if (_generator != null) return;
    if (_modelPath == null) {
      // Fallback: get path if ensureDownloaded wasn't called
      _modelPath = await _modelManager.getModelPath(
        ModelRegistry.medgemma15_4b.id,
      );
    }

    _generator = EdgeVeda();
    await _generator!.init(EdgeVedaConfig(
      modelPath: _modelPath!,
      useGpu: true,
      numThreads: 4,
      contextLength: 2048,
      maxMemoryMb: 1200,
    ));
  }

  /// Translate medical text from one language to another.
  ///
  /// On first call, loads MedGemma into GPU (~5s). Subsequent calls are fast.
  /// Creates a fresh [ChatSession] per call with a medical interpreter
  /// system prompt. Uses low temperature (0.2) for accuracy.
  Future<String> translate(
    String text,
    AppLanguage from,
    AppLanguage to,
  ) async {
    // Lazy-load model on first translation
    await _loadModel();

    final session = ChatSession(
      edgeVeda: _generator!,
      templateFormat: ChatTemplateFormat.gemma3,
      systemPrompt:
          'You are a translator. When given text, translate it to the '
          'requested language. Output ONLY the translation. No explanations.',
    );

    final prompt = 'Translate to ${to.displayName}: $text';

    final reply = await session.send(
      prompt,
      options: const GenerateOptions(
        temperature: 0.3,
        maxTokens: 256,
      ),
    );

    return reply.content
        .replaceAll(_specialTokenPattern, '')
        .trim();
  }

  /// Dispose all SDK resources.
  void dispose() {
    _generator?.dispose();
    _generator = null;
  }

  /// Download a model if not already cached.
  Future<String> _ensureModel(
    ModelInfo model,
    void Function(double) onProgress,
  ) async {
    final isDownloaded = await _modelManager.isModelDownloaded(model.id);
    if (isDownloaded) {
      return _modelManager.getModelPath(model.id);
    }

    final sub = _modelManager.downloadProgress.listen(
      (p) => onProgress(p.progress),
    );
    final path = await _modelManager.downloadModel(model);
    await sub.cancel();
    return path;
  }
}
