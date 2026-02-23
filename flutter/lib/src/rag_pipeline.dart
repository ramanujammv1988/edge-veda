/// End-to-end RAG (Retrieval-Augmented Generation) pipeline for on-device use.
///
/// Combines text embeddings, vector search, and LLM generation into a single
/// pipeline that retrieves relevant context before generating responses.
///
/// Example:
/// ```dart
/// final rag = RagPipeline(
///   edgeVeda: edgeVeda,
///   index: vectorIndex,
/// );
///
/// // Add documents
/// await rag.addDocument('doc1', 'Flutter is a UI toolkit...');
///
/// // Query with RAG
/// final response = await rag.query('What is Flutter?');
/// print(response.text); // Uses retrieved context
/// ```
library;

import 'edge_veda_impl.dart';
import 'types.dart';
import 'vector_index.dart';
import 'fts_index.dart';

/// Configuration for the RAG pipeline
class RagConfig {
  /// Number of documents to retrieve for context
  final int topK;

  /// Minimum similarity score to include a document (0.0-1.0)
  final double minScore;

  /// Template for injecting retrieved context into the prompt
  /// Use {context} for retrieved text and {query} for the user query
  final String promptTemplate;

  /// Maximum context length in characters (to prevent overflow)
  final int maxContextLength;

  const RagConfig({
    this.topK = 3,
    this.minScore = 0.0,
    this.promptTemplate = 'Use the following context to answer the question.\n\nContext:\n{context}\n\nQuestion: {query}\n\nAnswer:',
    this.maxContextLength = 2000,
  });
}

/// End-to-end RAG pipeline: embed query -> search index -> inject context -> generate
class RagPipeline {
  final EdgeVeda _embedder;
  final EdgeVeda _generator;
  final VectorIndex _index;
  final FtsIndex _ftsIndex;
  final RagConfig config;

  /// Create a RAG pipeline with a single EdgeVeda instance for both embedding
  /// and generation. Suitable when one model handles both tasks.
  RagPipeline({
    required EdgeVeda edgeVeda,
    required VectorIndex index,
    required FtsIndex ftsIndex,
    this.config = const RagConfig(),
  })  : _embedder = edgeVeda,
        _generator = edgeVeda,
        _index = index,
        _ftsIndex = ftsIndex;

  /// Create a RAG pipeline with separate embedding and generation models.
  ///
  /// Use this when your embedding model (e.g., all-MiniLM-L6-v2) is different
  /// from your generation model (e.g., Llama 3.2 1B). This is the recommended
  /// configuration for production RAG.
  RagPipeline.withModels({
    required EdgeVeda embedder,
    required EdgeVeda generator,
    required VectorIndex index,
    required FtsIndex ftsIndex,
    this.config = const RagConfig(),
  })  : _embedder = embedder,
        _generator = generator,
        _index = index,
        _ftsIndex = ftsIndex;

  /// The underlying vector index
  VectorIndex get index => _index;

  /// Add a document to the index
  ///
  /// Embeds the text and stores it in the vector index with the given ID.
  /// Optional metadata is stored alongside the vector for retrieval.
  Future<void> addDocument(
    String id,
    String text, {
    Map<String, dynamic>? metadata,
  }) async {
    final result = await _embedder.embed(text);
    _index.add(
      id,
      result.embedding,
      metadata: {
        'text': text,
        ...?metadata,
      },
    );
    _ftsIndex.add(id, text);
  }

  /// Add multiple documents in batch
  Future<void> addDocuments(Map<String, String> documents) async {
    for (final entry in documents.entries) {
      await addDocument(entry.key, entry.value);
    }
  }

  /// Query with RAG: embed query -> retrieve context -> generate response
  ///
  /// Returns a [GenerateResponse] with the LLM's answer augmented by
  /// retrieved context from the vector index.
  Future<GenerateResponse> query(
    String queryText, {
    GenerateOptions? options,
  }) async {
    // Step 1: Search the vector/FTS index (Hybrid search)
    final results = await retrieve(
      queryText,
      k: config.topK,
    );

    // Step 3: Filter by minimum score and build context
    final relevantDocs = results
        .where((r) => r.score >= config.minScore)
        .toList();

    final contextParts = <String>[];
    int totalLength = 0;
    for (final doc in relevantDocs) {
      final text = doc.metadata['text'] as String? ?? '';
      if (totalLength + text.length > config.maxContextLength) break;
      contextParts.add(text);
      totalLength += text.length;
    }

    final context = contextParts.join('\n\n');

    // Step 4: Build augmented prompt
    final augmentedPrompt = config.promptTemplate
        .replaceAll('{context}', context)
        .replaceAll('{query}', queryText);

    // Step 5: Generate response
    final response = await _generator.generate(
      augmentedPrompt,
      options: options,
    );

    return response;
  }

  /// Query with RAG and streaming response
  Stream<TokenChunk> queryStream(
    String queryText, {
    GenerateOptions? options,
    CancelToken? cancelToken,
  }) async* {
    // Step 1: Search the vector/FTS index (Hybrid search)
    final results = await retrieve(
      queryText,
      k: config.topK,
    );

    // Step 3: Build context
    final contextParts = <String>[];
    int totalLength = 0;
    final matchedDocs = results.where((r) => r.score >= config.minScore).toList();
    for (final doc in matchedDocs) {
      final text = doc.metadata['text'] as String? ?? '';
      if (totalLength + text.length > config.maxContextLength) break;
      contextParts.add(text);
      totalLength += text.length;
    }

    final context = contextParts.join('\n\n');

    // Step 4: Build augmented prompt
    final augmentedPrompt = config.promptTemplate
        .replaceAll('{context}', context)
        .replaceAll('{query}', queryText);

    // Step 5: Stream response
    yield* _generator.generateStream(
      augmentedPrompt,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Retrieve similar documents without generating (useful for debugging)
  Future<List<SearchResult>> retrieve(
    String queryText, {
    int? k,
  }) async {
    final searchK = k ?? config.topK;

    // 1. Vector Search
    final queryEmbedding = await _embedder.embed(queryText);
    final vectorResults = _index.query(
      queryEmbedding.embedding,
      k: searchK,
    );

    // 2. Text Search (BM25)
    final textScores = _ftsIndex.search(queryText);
    final sortedTextResults = textScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final bestTextResults = sortedTextResults.take(searchK).toList();

    // 3. Reciprocal Rank Fusion (RRF)
    final fusedScores = <String, double>{};
    const rrfc = 60.0; // standard constant for RRF

    for (int i = 0; i < vectorResults.length; i++) {
      final id = vectorResults[i].id;
      fusedScores[id] = (fusedScores[id] ?? 0.0) + (1.0 / (rrfc + i + 1));
    }

    for (int i = 0; i < bestTextResults.length; i++) {
      final id = bestTextResults[i].key;
      fusedScores[id] = (fusedScores[id] ?? 0.0) + (1.0 / (rrfc + i + 1));
    }

    // Convert back to SearchResult, sorting by fused score
    final sortedFused = fusedScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Normalize fused scores to [0.0 - 1.0] so they survive upstream thresholds
    double maxScore = sortedFused.isNotEmpty ? sortedFused.first.value : 0.0;

    final finalResults = <SearchResult>[];
    for (final entry in sortedFused) {
      final id = entry.key;
      final rawScore = entry.value;

      Map<String, dynamic>? metadata;
      try {
        metadata = vectorResults.firstWhere((r) => r.id == id).metadata;
      } catch (_) {
        // Fallback: If VectorIndex didn't return this in topK, pull the text from FtsIndex
        final docText = _ftsIndex.getDocument(id);
        if (docText != null) {
          metadata = {'text': docText};
        }
      }

      finalResults.add(SearchResult(
        id: id,
        score: maxScore > 0 ? (rawScore / maxScore) : rawScore, // Normalize
        metadata: metadata ?? {},
      ));
    }

    return finalResults.take(searchK).toList();
  }
}
