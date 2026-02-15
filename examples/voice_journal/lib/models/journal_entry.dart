import 'package:intl/intl.dart';

/// A single voice journal entry with transcript, summary, and tags.
class JournalEntry {
  /// SQLite auto-increment ID (null before insertion).
  final int? id;

  /// When the entry was recorded.
  final DateTime createdAt;

  /// Raw STT transcript.
  final String transcript;

  /// LLM-generated summary (null if not yet processed).
  final String? summary;

  /// Comma-separated tags from LLM (e.g., "#work #meeting #planning").
  final String? tags;

  /// Recording duration in seconds.
  final int? durationSeconds;

  JournalEntry({
    this.id,
    required this.createdAt,
    required this.transcript,
    this.summary,
    this.tags,
    this.durationSeconds,
  });

  /// Deserialize from SQLite row.
  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      id: map['id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      transcript: map['transcript'] as String,
      summary: map['summary'] as String?,
      tags: map['tags'] as String?,
      durationSeconds: map['duration_seconds'] as int?,
    );
  }

  /// Serialize for SQLite insertion.
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'created_at': createdAt.toIso8601String(),
      'transcript': transcript,
      'summary': summary,
      'tags': tags,
      'duration_seconds': durationSeconds,
    };
  }

  /// Create a copy with updated fields.
  JournalEntry copyWith({
    int? id,
    DateTime? createdAt,
    String? transcript,
    String? summary,
    String? tags,
    int? durationSeconds,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  /// Human-readable date string: "Feb 15, 2026 3:09 PM".
  String get displayDate => DateFormat('MMM d, yyyy h:mm a').format(createdAt);

  /// First 100 characters of summary (or transcript if no summary).
  String get shortSummary {
    final text = summary ?? transcript;
    if (text.length <= 100) return text;
    return '${text.substring(0, 100)}...';
  }

  /// Parsed tag list (splits comma-separated or space-separated tags).
  List<String> get tagList {
    if (tags == null || tags!.trim().isEmpty) return [];
    return tags!
        .split(RegExp(r'[,\s]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  /// Duration formatted as "2m 34s".
  String get formattedDuration {
    if (durationSeconds == null) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Word count of the transcript.
  int get wordCount =>
      transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}
