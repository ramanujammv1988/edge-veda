import 'package:edge_veda/edge_veda.dart';

import 'pdf_service.dart';

/// Service that wraps all Edge Veda SDK interaction for the Document Q&A app.
///
/// Manages model download, embedding, vector indexing, and RAG-powered Q&A.
class RagService {
  final ModelManager _modelManager = ModelManager();

  EdgeVeda? _embedder;
  EdgeVeda? _generator;
  RagPipeline? _pipeline;
  VectorIndex? _index;

  /// Whether the service is fully initialized and ready for queries.
  bool get isReady => _pipeline != null;

  /// Whether initialization is currently in progress.
  bool isInitializing = false;

  /// Name of the currently loaded document.
  String? documentName;

  /// Number of chunks in the current document index.
  int chunkCount = 0;

  /// Initialize the service: download models, create embedder and generator.
  ///
  /// [onStatus] is called with status messages (e.g., "Downloading model...").
  /// [onProgress] is called with download progress (0.0 to 1.0).
  Future<void> init({
    required Function(String) onStatus,
    required Function(double) onProgress,
  }) async {
    isInitializing = true;

    try {
      // Download embedding model
      onStatus('Downloading embedding model...');
      final embModel = ModelRegistry.allMiniLmL6V2;
      late final String embPath;

      final embDownloaded = await _modelManager.isModelDownloaded(embModel.id);
      if (!embDownloaded) {
        // Listen for download progress
        final sub = _modelManager.downloadProgress.listen((p) {
          onProgress(p.progressPercent / 100.0 * 0.3); // 0-30%
        });
        embPath = await _modelManager.downloadModel(embModel);
        await sub.cancel();
      } else {
        embPath = await _modelManager.getModelPath(embModel.id);
      }
      onProgress(0.3);

      // Download generation model
      onStatus('Downloading generation model...');
      final genModel = ModelRegistry.llama32_1b;
      late final String genPath;

      final genDownloaded = await _modelManager.isModelDownloaded(genModel.id);
      if (!genDownloaded) {
        final sub = _modelManager.downloadProgress.listen((p) {
          onProgress(0.3 + p.progressPercent / 100.0 * 0.4); // 30-70%
        });
        genPath = await _modelManager.downloadModel(genModel);
        await sub.cancel();
      } else {
        genPath = await _modelManager.getModelPath(genModel.id);
      }
      onProgress(0.7);

      // Initialize embedder
      onStatus('Initializing embedding model...');
      _embedder = EdgeVeda();
      await _embedder!.init(EdgeVedaConfig(
        modelPath: embPath,
        useGpu: true,
        numThreads: 4,
        contextLength: 512, // Embedding models need minimal context window
        maxMemoryMb: 256, // MiniLM is small (~46 MB model + overhead)
        verbose: false,
      ));
      onProgress(0.85);

      // Initialize generator
      onStatus('Initializing generation model...');
      _generator = EdgeVeda();
      await _generator!.init(EdgeVedaConfig(
        modelPath: genPath,
        useGpu: true,
        numThreads: 4,
        contextLength: 2048, // Enough for RAG prompt (query + retrieved chunks + generation)
        maxMemoryMb: 1024, // Llama 3.2 1B needs ~400-550 MB; 1024 provides headroom
        verbose: false,
      ));
      onProgress(0.95);

      // Create empty vector index (will be populated when document is loaded)
      _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality
      onStatus('Ready');
      onProgress(1.0);
    } finally {
      isInitializing = false;
    }
  }

  /// Index a document for RAG-powered Q&A.
  ///
  /// Chunks the text, embeds each chunk, builds the vector index, and creates
  /// the RAG pipeline. Calls [onChunkProgress] with (current, total) during
  /// the embedding loop.
  Future<void> indexDocument(
    String text,
    String fileName, {
    Function(int, int)? onChunkProgress,
  }) async {
    final chunks = PdfService.chunkText(text);
    if (chunks.isEmpty) throw Exception('No text chunks extracted');

    // Reset index for new document
    _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality

    // Embed and index each chunk
    for (int i = 0; i < chunks.length; i++) {
      final result = await _embedder!.embed(chunks[i]);
      _index!.add(
        'chunk_$i',
        result.embedding,
        metadata: {'text': chunks[i]},
      );
      onChunkProgress?.call(i + 1, chunks.length);
    }

    // Create RAG pipeline with separate embedder and generator
    _pipeline = RagPipeline.withModels(
      embedder: _embedder!,
      generator: _generator!,
      index: _index!,
    );

    documentName = fileName;
    chunkCount = chunks.length;
  }

  /// Query the indexed document with RAG-powered streaming.
  ///
  /// Returns a stream of [TokenChunk] from the RAG pipeline.
  Stream<TokenChunk> query(String question) {
    if (_pipeline == null) {
      throw StateError('No document indexed. Call indexDocument() first.');
    }
    return _pipeline!.queryStream(question);
  }

  /// Remove the current document and reset the pipeline.
  void removeDocument() {
    _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality
    _pipeline = null;
    documentName = null;
    chunkCount = 0;
  }

  /// Dispose all resources.
  void dispose() {
    _embedder?.dispose();
    _generator?.dispose();
    _pipeline = null;
    _index = null;
  }
}
