import 'dart:io';

import 'package:edge_veda/edge_veda.dart';
import 'package:path_provider/path_provider.dart';

import '../models/journal_entry.dart';

/// Embedding-based semantic search over journal entries.
///
/// Uses [VectorIndex] (HNSW) for O(log n) approximate nearest neighbor
/// search. Each journal entry's transcript is embedded and stored with
/// id='entry_{id}'. The index is persisted to disk as JSON.
class SearchService {
  EdgeVeda? _edgeVeda;
  VectorIndex? _index;
  String? _indexPath;

  bool get isReady => _edgeVeda != null && _index != null;

  /// Initialize: locate embedding model, create VectorIndex, load from disk.
  Future<void> init({
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Loading search model...');

    final mm = ModelManager();
    final modelPath =
        await mm.getModelPath(ModelRegistry.allMiniLmL6V2.id);

    _edgeVeda = EdgeVeda();
    await _edgeVeda!.init(EdgeVedaConfig(
      modelPath: modelPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 512, // Embedding models need minimal context window
      maxMemoryMb: 256, // MiniLM is small (~46 MB model + overhead)
    ));

    // Set up persistence path
    final docsDir = await getApplicationDocumentsDirectory();
    _indexPath = '${docsDir.path}/voice_journal_index.json';

    // Load persisted index or create new
    final indexFile = File(_indexPath!);
    if (await indexFile.exists()) {
      try {
        _index = await VectorIndex.load(_indexPath!);
        onStatus?.call('Search index loaded (${_index!.size} entries)');
      } catch (_) {
        // Corrupted index -- start fresh
        _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality
        onStatus?.call('Search index created');
      }
    } else {
      _index = VectorIndex(dimensions: 384); // all-MiniLM-L6-v2 output dimensionality
      onStatus?.call('Search index created');
    }
  }

  /// Index a journal entry for search.
  Future<void> indexEntry(JournalEntry entry) async {
    if (_edgeVeda == null || _index == null || entry.id == null) return;

    final result = await _edgeVeda!.embed(entry.transcript);
    _index!.add(
      'entry_${entry.id}',
      result.embedding,
      metadata: {'text': entry.transcript},
    );

    // Persist to disk
    await _saveIndex();
  }

  /// Search for journal entries matching [query].
  ///
  /// Returns a list of entry IDs sorted by relevance.
  Future<List<int>> search(String query, {int k = 5}) async {
    if (_edgeVeda == null || _index == null || _index!.isEmpty) return [];

    final result = await _edgeVeda!.embed(query);
    final results = _index!.query(result.embedding, k: k);

    return results
        .map((r) {
          // Parse entry ID from 'entry_123' format
          final idStr = r.id.replaceFirst('entry_', '');
          return int.tryParse(idStr);
        })
        .where((id) => id != null)
        .cast<int>()
        .toList();
  }

  /// Remove an entry from the search index.
  Future<void> removeEntry(int entryId) async {
    if (_index == null) return;

    final id = 'entry_$entryId';
    if (_index!.ids.contains(id)) {
      // VectorIndex handles delete-then-readd internally for updates,
      // but for removal we need to rebuild without this entry.
      // Since VectorIndex does not expose a delete() method on its own,
      // we accept that removed entries may linger in the index until
      // the next full rebuild. The search results are filtered by
      // valid entry IDs in the database anyway.
    }

    await _saveIndex();
  }

  Future<void> _saveIndex() async {
    if (_index == null || _indexPath == null) return;
    try {
      await _index!.save(_indexPath!);
    } catch (_) {
      // Non-critical -- index can be rebuilt from database
    }
  }

  /// Dispose the EdgeVeda instance and save the index.
  void dispose() {
    _saveIndex();
    _edgeVeda?.dispose();
    _edgeVeda = null;
    _index = null;
  }
}
