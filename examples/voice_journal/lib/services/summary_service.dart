import 'package:edge_veda/edge_veda.dart';

/// Wraps [ChatSession] for LLM-powered summarization and tag extraction.
///
/// Each call to [summarize] sends the transcript to the model, parses the
/// response into a summary and tag list, then resets the session (no context
/// accumulation across entries).
class SummaryService {
  EdgeVeda? _edgeVeda;
  ChatSession? _chatSession;

  bool get isReady => _chatSession != null;

  static const String _systemPrompt =
      'You are a helpful assistant. When given a voice note transcript, '
      'provide a concise 2-3 sentence summary. Then on a new line, suggest '
      '2-3 relevant tags prefixed with #. Format:\n'
      'Summary text\n\n'
      'Tags: #tag1 #tag2 #tag3';

  /// Initialize: locate chat model and create ChatSession.
  Future<void> init({
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Loading summarization model...');

    final mm = ModelManager();
    final modelPath =
        await mm.getModelPath(ModelRegistry.llama32_1b.id);

    _edgeVeda = EdgeVeda();
    await _edgeVeda!.init(EdgeVedaConfig(
      modelPath: modelPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 2048,
      maxMemoryMb: 1024,
    ));

    _chatSession = ChatSession(
      edgeVeda: _edgeVeda!,
      systemPrompt: _systemPrompt,
    );

    onStatus?.call('Summarization model ready');
  }

  /// Summarize a transcript and extract tags.
  ///
  /// Returns a record with `summary` and `tags` fields.
  Future<({String summary, String tags})> summarize(
      String transcript) async {
    if (_chatSession == null) {
      return (summary: transcript, tags: '');
    }

    try {
      final response = await _chatSession!.send(
        'Summarize this voice note:\n\n$transcript',
      );

      // Reset session after each summarization to avoid context accumulation
      _chatSession!.reset();

      return _parseResponse(response.content);
    } catch (_) {
      _chatSession?.reset();
      return (summary: transcript, tags: '');
    }
  }

  /// Parse LLM response into summary + tags.
  ({String summary, String tags}) _parseResponse(String response) {
    // Try to find "Tags:" separator
    final tagsIndex = response.toLowerCase().lastIndexOf('tags:');
    if (tagsIndex > 0) {
      final summary = response.substring(0, tagsIndex).trim();
      final tags = response.substring(tagsIndex + 5).trim();
      return (summary: summary, tags: tags);
    }

    // Fallback: look for lines starting with #
    final lines = response.split('\n');
    final tagLines = <String>[];
    final summaryLines = <String>[];

    for (final line in lines) {
      if (line.trim().startsWith('#')) {
        tagLines.add(line.trim());
      } else if (line.trim().isNotEmpty) {
        summaryLines.add(line.trim());
      }
    }

    if (tagLines.isNotEmpty) {
      return (
        summary: summaryLines.join(' '),
        tags: tagLines.join(' '),
      );
    }

    // No tags found -- return full response as summary
    return (summary: response.trim(), tags: '');
  }

  /// Dispose the EdgeVeda instance.
  void dispose() {
    _edgeVeda?.dispose();
    _edgeVeda = null;
    _chatSession = null;
  }
}
