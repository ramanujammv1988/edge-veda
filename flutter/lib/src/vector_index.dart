/// Pure Dart vector index for on-device RAG using HNSW algorithm.
///
/// Stores document embeddings and retrieves the k most similar documents
/// for a given query embedding. Uses cosine distance by default (optimal
/// for L2-normalized embeddings from ev_embed).
///
/// Backed by [local_hnsw](https://pub.dev/packages/local_hnsw) -- pure Dart,
/// zero native dependencies, O(log n) approximate nearest neighbor search.
///
/// Example:
/// ```dart
/// final index = VectorIndex(dimensions: 384);
/// index.add('doc1', [0.1, 0.2, ...], metadata: {'title': 'Hello'});
/// final results = index.query([0.1, 0.2, ...], k: 5);
/// for (final r in results) {
///   print('${r.id}: ${r.score}');
/// }
/// await index.save('/path/to/index.json');
/// final loaded = await VectorIndex.load('/path/to/index.json');
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:local_hnsw/local_hnsw.dart';
import 'package:local_hnsw/local_hnsw.item.dart';

/// HNSW-backed vector index for on-device similarity search.
///
/// Each vector is associated with a string [id] and optional [metadata].
/// The index uses cosine distance by default, which is correct for
/// L2-normalized embeddings produced by ev_embed.
class VectorIndex {
  /// Number of dimensions per embedding vector.
  final int dimensions;

  /// The underlying HNSW index.
  late final LocalHNSW<String> _index;

  /// Metadata stored per document ID.
  final Map<String, Map<String, dynamic>> _metadata = {};

  /// Set of IDs currently in the index (tracks membership).
  final Set<String> _ids = {};

  /// Create a new empty vector index.
  ///
  /// [dimensions] must match the embedding model's output size
  /// (e.g., 384 for all-MiniLM, 768 for nomic-embed-text).
  VectorIndex({
    required this.dimensions,
  }) {
    _index = LocalHNSW<String>(
      dim: dimensions,
      metric: LocalHnswMetric.cosine,
    );
  }

  /// Private constructor for [load] factory.
  VectorIndex._internal({required this.dimensions}) {
    _index = LocalHNSW<String>(
      dim: dimensions,
      metric: LocalHnswMetric.cosine,
    );
  }

  /// Number of vectors in the index.
  int get size => _ids.length;

  /// Whether the index is empty.
  bool get isEmpty => _ids.isEmpty;

  /// All document IDs currently in the index.
  Iterable<String> get ids => _ids;

  /// Add a vector with an [id] and optional [metadata].
  ///
  /// Throws [ArgumentError] if [embedding] length does not match [dimensions].
  /// If an entry with the same [id] already exists, it is replaced.
  void add(String id, List<double> embedding,
      {Map<String, dynamic>? metadata}) {
    if (embedding.length != dimensions) {
      throw ArgumentError(
        'Embedding dimension ${embedding.length} does not match '
        'index dimension $dimensions',
      );
    }

    // If id already exists, delete first to avoid duplicates
    if (_ids.contains(id)) {
      _index.delete(id);
    }

    _index.add(LocalHnswItem<String>(item: id, vector: embedding));
    _ids.add(id);
    _metadata[id] = metadata ?? {};
  }

  /// Query the index for the [k] nearest neighbors to [embedding].
  ///
  /// Returns results sorted by similarity score (highest first).
  /// Throws [ArgumentError] if [embedding] length does not match [dimensions].
  /// Returns an empty list if the index is empty.
  List<SearchResult> query(List<double> embedding, {int k = 5}) {
    if (embedding.length != dimensions) {
      throw ArgumentError(
        'Query dimension ${embedding.length} does not match '
        'index dimension $dimensions',
      );
    }

    if (_ids.isEmpty) return [];

    final result = _index.search(embedding, k);

    return result.items.map((item) {
      return SearchResult(
        id: item.item,
        // Convert cosine distance to similarity: similarity = 1 - distance
        score: 1.0 - item.distance,
        metadata: _metadata[item.item] ?? {},
      );
    }).toList();
  }

  /// Delete a vector by [id].
  ///
  /// Returns true if the entry was found and deleted, false otherwise.
  bool delete(String id) {
    if (!_ids.contains(id)) return false;

    final deleted = _index.delete(id);
    if (deleted) {
      _ids.remove(id);
      _metadata.remove(id);
    }
    return deleted;
  }

  /// Save the index to a JSON file at [path].
  ///
  /// The file contains all vectors, metadata, and HNSW graph structure.
  /// Use [load] to restore the index from this file.
  Future<void> save(String path) async {
    final indexData = _index.save(encodeItem: (id) => id);

    final data = {
      'version': 1,
      'dimensions': dimensions,
      'metadata': _metadata,
      'index': indexData,
    };

    final file = File(path);
    await file.writeAsString(jsonEncode(data));
  }

  /// Load an index from a JSON file at [path].
  ///
  /// Throws if the file does not exist or is malformed.
  static Future<VectorIndex> load(String path) async {
    final file = File(path);
    final contents = await file.readAsString();
    final data = jsonDecode(contents) as Map<String, dynamic>;

    final dims = data['dimensions'] as int;
    final vectorIndex = VectorIndex._internal(dimensions: dims);

    // Restore metadata
    final meta = data['metadata'] as Map<String, dynamic>;
    for (final entry in meta.entries) {
      vectorIndex._metadata[entry.key] =
          Map<String, dynamic>.from(entry.value as Map);
      vectorIndex._ids.add(entry.key);
    }

    // Restore HNSW index from saved data (re-inserts all vectors)
    final indexData = data['index'] as Map<String, dynamic>;
    vectorIndex._index = LocalHNSW.load<String>(
      json: indexData,
      dim: dims,
      decodeItem: (encoded) => encoded,
      metric: LocalHnswMetric.cosine,
    );

    return vectorIndex;
  }

  /// Create a new empty index (factory for API consistency with [load]).
  static VectorIndex create({required int dimensions}) {
    return VectorIndex(dimensions: dimensions);
  }
}

/// Result from a vector similarity search.
class SearchResult {
  /// Document ID.
  final String id;

  /// Similarity score (0.0 = dissimilar, 1.0 = identical).
  ///
  /// Computed as `1.0 - cosine_distance`. For L2-normalized embeddings,
  /// this equals the cosine similarity (dot product).
  final double score;

  /// Associated metadata provided when the vector was added.
  final Map<String, dynamic> metadata;

  /// Create a search result.
  const SearchResult({
    required this.id,
    required this.score,
    required this.metadata,
  });

  @override
  String toString() =>
      'SearchResult(id: $id, score: ${score.toStringAsFixed(4)})';
}
