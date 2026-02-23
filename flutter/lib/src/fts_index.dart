import 'dart:math' as math;

/// A simple pure-Dart implementation of BM25 (Best Matching 25) full-text search.
/// Designed for on-device Keyword Search/FTS in Hybrid RAG pipelines.
class FtsIndex {
  final Map<String, List<String>> _documentTokens = {};
  final Map<String, int> _documentLengths = {};

  // Inverted index: word -> { docId -> frequency }
  final Map<String, Map<String, int>> _invertedIndex = {};

  // Document frequency: word -> number of documents containing the word
  final Map<String, int> _df = {};

  // Store the raw text of the document
  final Map<String, String> _documents = {};

  double _avgdl = 0.0;
  int _totalDocs = 0;

  // BM25 parameters
  final double k1;
  final double b;

  FtsIndex({this.k1 = 1.2, this.b = 0.75});

  /// Tokenize text into words (lowercase, removes punctuation).
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Add a document to the FTS index.
  void add(String id, String text) {
    if (_documentTokens.containsKey(id)) {
      remove(id);
    }

    _documents[id] = text;

    final tokens = _tokenize(text);
    _documentTokens[id] = tokens;
    _documentLengths[id] = tokens.length;

    final Map<String, int> tf = {};
    for (final token in tokens) {
      tf[token] = (tf[token] ?? 0) + 1;
    }

    for (final entry in tf.entries) {
      final textToken = entry.key;
      final freq = entry.value;

      _invertedIndex.putIfAbsent(textToken, () => {});
      _invertedIndex[textToken]![id] = freq;

      _df[textToken] = (_df[textToken] ?? 0) + 1;
    }

    _totalDocs++;
    _updateAvgdl();
  }

  /// Remove a document from the FTS index.
  void remove(String id) {
    if (!_documentTokens.containsKey(id)) return;

    final tokens = _documentTokens[id]!;
    final uniqueTokens = tokens.toSet();

    for (final token in uniqueTokens) {
      _invertedIndex[token]?.remove(id);
      if (_invertedIndex[token]?.isEmpty ?? true) {
        _invertedIndex.remove(token);
      }

      if (_df.containsKey(token)) {
        _df[token] = _df[token]! - 1;
        if (_df[token]! <= 0) {
          _df.remove(token);
        }
      }
    }

    _documents.remove(id);
    _documentTokens.remove(id);
    _documentLengths.remove(id);
    _totalDocs--;
    _updateAvgdl();
  }

  void _updateAvgdl() {
    if (_totalDocs == 0) {
      _avgdl = 0;
      return;
    }
    int totalLength = _documentLengths.values.fold(0, (sum, len) => sum + len);
    _avgdl = totalLength / _totalDocs;
  }

  /// Calculate IDF for a term.
  double _idf(String term) {
    final df = _df[term] ?? 0;
    // Standard BM25 IDF formulation
    return math.log((_totalDocs - df + 0.5) / (df + 0.5) + 1.0);
  }

  /// Search the index for a query. Returns a Map of {docId: score}.
  Map<String, double> search(String query) {
    final queryTokens = _tokenize(query);
    final Map<String, double> scores = {};

    for (final token in queryTokens) {
      if (!_invertedIndex.containsKey(token)) continue;

      final idf = _idf(token);
      final docs = _invertedIndex[token]!;

      for (final entry in docs.entries) {
        final docId = entry.key;
        final freq = entry.value;
        final docLen = _documentLengths[docId]!;

        // BM25 scoring formula
        final numerator = freq * (k1 + 1);
        final denominator = freq + k1 * (1 - b + b * (docLen / _avgdl));
        final score = idf * (numerator / denominator);

        scores[docId] = (scores[docId] ?? 0.0) + score;
      }
    }

    return scores;
  }

  /// Retrieve the original text for a given document ID.
  String? getDocument(String id) {
    return _documents[id];
  }
}
