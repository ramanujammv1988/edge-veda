import 'package:edge_veda/edge_veda.dart';

import 'pdf_service.dart';

/// Result of confidence tracking across a streamed response.
class ConfidenceResult {
  /// Average confidence across all tokens that reported a score (0.0-1.0).
  final double avgConfidence;

  /// Whether any token during generation recommended cloud handoff.
  final bool needsHandoff;

  const ConfidenceResult({
    required this.avgConfidence,
    required this.needsHandoff,
  });
}

/// SDK wrapper that manages two-model RAG with confidence scoring.
///
/// Uses all-MiniLM-L6-v2 for embeddings and Llama 3.2 1B for generation.
/// Each query streams tokens while accumulating confidence data so the UI
/// can display a badge and cloud-handoff banner after generation completes.
class HealthRagService {
  final ModelManager _modelManager = ModelManager();

  EdgeVeda? _embedder;
  EdgeVeda? _generator;
  RagPipeline? _pipeline;
  VectorIndex? _index;

  String? _documentName;
  int _chunkCount = 0;

  // Confidence accumulator -- updated during streaming, read after.
  double _totalConfidence = 0;
  int _confidenceTokenCount = 0;
  bool _needsHandoff = false;

  /// Whether both models are loaded and the pipeline is ready.
  bool get isReady => _pipeline != null;

  /// Name of the currently loaded document (null if none).
  String? get documentName => _documentName;

  /// Number of chunks in the current document index.
  int get chunkCount => _chunkCount;

  /// Confidence result from the most recently completed query.
  ConfidenceResult get lastConfidence => ConfidenceResult(
        avgConfidence: _confidenceTokenCount > 0
            ? _totalConfidence / _confidenceTokenCount
            : 0.0,
        needsHandoff: _needsHandoff,
      );

  /// Initialize both embedding and generation models.
  ///
  /// Calls [onStatus] with human-readable progress descriptions and
  /// [onProgress] with 0.0-1.0 download progress.
  Future<void> init({
    required void Function(String status) onStatus,
    required void Function(double progress) onProgress,
  }) async {
    // 1. Download / locate embedding model
    onStatus('Downloading model 1/2: Embedding (46 MB)...');
    final embPath = await _ensureModel(
      ModelRegistry.allMiniLmL6V2,
      onProgress,
    );

    // 2. Download / locate generation model
    onStatus('Downloading model 2/2: Llama 3.2 1B (668 MB)...');
    final genPath = await _ensureModel(
      ModelRegistry.llama32_1b,
      onProgress,
    );

    // 3. Init embedder
    onStatus('Initializing embedding model...');
    _embedder = EdgeVeda();
    await _embedder!.init(EdgeVedaConfig(
      modelPath: embPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 512, // Embedding models need minimal context window
      maxMemoryMb: 256, // MiniLM is small (~46 MB model + overhead)
    ));

    // 4. Init generator
    onStatus('Initializing chat model...');
    _generator = EdgeVeda();
    await _generator!.init(EdgeVedaConfig(
      modelPath: genPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 2048, // Enough for RAG prompt (query + retrieved chunks + generation)
      maxMemoryMb: 1024, // Llama 3.2 1B needs ~400-550 MB; 1024 provides headroom
    ));

    onStatus('Models ready');
  }

  /// Index a document for RAG retrieval.
  ///
  /// Extracts text, chunks it, embeds each chunk, and builds the vector
  /// index. Calls [onProgress] with (completed, total) chunk counts.
  Future<void> indexDocument(
    String filePath,
    String fileName, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final text = await PdfService.extractText(filePath);
    if (text.trim().isEmpty) {
      throw Exception('Document is empty or could not be read');
    }

    final chunks = PdfService.chunkText(text);
    if (chunks.isEmpty) {
      throw Exception('Could not extract text chunks from document');
    }

    // Batch-embed all chunks
    final embeddings = await _embedder!.embedBatch(
      chunks,
      onProgress: (completed, total) {
        onProgress?.call(completed, total);
      },
    );

    // Build vector index
    _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality
    for (int i = 0; i < chunks.length; i++) {
      _index!.add(
        'chunk_$i',
        embeddings[i].embedding,
        metadata: {'text': chunks[i]},
      );
    }

    // Create RAG pipeline
    _pipeline = RagPipeline.withModels(
      embedder: _embedder!,
      generator: _generator!,
      index: _index!,
    );

    _documentName = fileName;
    _chunkCount = chunks.length;
  }

  /// Query the document with confidence scoring enabled.
  ///
  /// Returns a stream of [TokenChunk]s. After the stream completes,
  /// read [lastConfidence] to get the aggregated confidence result.
  Stream<TokenChunk> query(String question) async* {
    if (_pipeline == null) {
      throw StateError('Pipeline not initialized. Call indexDocument first.');
    }

    // Reset confidence accumulator
    _totalConfidence = 0;
    _confidenceTokenCount = 0;
    _needsHandoff = false;

    const options = GenerateOptions(
      confidenceThreshold: 0.3, // Tokens below 30% confidence trigger needsCloudHandoff flag
      temperature: 0.3,
      maxTokens: 512, // Cap response length for health Q&A (focused answers)
    );

    final stream = _pipeline!.queryStream(question, options: options);

    await for (final chunk in stream) {
      // Accumulate confidence data
      if (chunk.confidence != null) {
        _totalConfidence += chunk.confidence!;
        _confidenceTokenCount++;
      }
      if (chunk.needsCloudHandoff) {
        _needsHandoff = true;
      }

      yield chunk;
    }
  }

  /// Remove the currently loaded document and reset the index.
  void removeDocument() {
    _pipeline = null;
    _index = null;
    _documentName = null;
    _chunkCount = 0;
    _totalConfidence = 0;
    _confidenceTokenCount = 0;
    _needsHandoff = false;
  }

  /// Dispose all SDK resources.
  void dispose() {
    _embedder?.dispose();
    _generator?.dispose();
    _pipeline = null;
    _index = null;
  }

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
