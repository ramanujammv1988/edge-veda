import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/journal_entry.dart';
import '../services/journal_db.dart';
import '../services/search_service.dart';
import '../theme.dart';

/// Detail view for a single journal entry.
///
/// Displays summary, tags, full transcript (expandable), and metadata.
class EntryDetailScreen extends StatefulWidget {
  final JournalEntry entry;
  final JournalDb journalDb;
  final SearchService searchService;

  const EntryDetailScreen({
    super.key,
    required this.entry,
    required this.journalDb,
    required this.searchService,
  });

  @override
  State<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends State<EntryDetailScreen> {
  bool _transcriptExpanded = false;

  Future<void> _deleteEntry() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This entry will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && widget.entry.id != null) {
      await widget.journalDb.deleteEntry(widget.entry.id!);
      await widget.searchService.removeEntry(widget.entry.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _copyToClipboard() {
    final text = StringBuffer();
    if (widget.entry.summary != null) {
      text.writeln('Summary:');
      text.writeln(widget.entry.summary);
      text.writeln();
    }
    if (widget.entry.tags != null && widget.entry.tags!.isNotEmpty) {
      text.writeln('Tags: ${widget.entry.tags}');
      text.writeln();
    }
    text.writeln('Transcript:');
    text.writeln(widget.entry.transcript);

    Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildSummarySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Summary',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.entry.summary ?? 'No summary available',
              style: TextStyle(
                color: widget.entry.summary != null
                    ? AppTheme.textPrimary
                    : AppTheme.textTertiary,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsSection() {
    final tags = widget.entry.tagList;
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: tags
            .map((tag) => Chip(
                  label: Text(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ))
            .toList(),
      ),
    );
  }

  Widget _buildTranscriptSection() {
    final transcript = widget.entry.transcript;
    final isLong = transcript.length > 200;
    final displayText = (!_transcriptExpanded && isLong)
        ? '${transcript.substring(0, 200)}...'
        : transcript;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Full Transcript',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isLong)
                  TextButton(
                    onPressed: () {
                      setState(
                          () => _transcriptExpanded = !_transcriptExpanded);
                    },
                    child: Text(
                      _transcriptExpanded ? 'Show less' : 'Show more',
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              displayText,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (widget.entry.formattedDuration.isNotEmpty) ...[
            const Icon(Icons.timer_outlined,
                size: 16, color: AppTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              widget.entry.formattedDuration,
              style: const TextStyle(
                  color: AppTheme.textTertiary, fontSize: 13),
            ),
            const SizedBox(width: 16),
          ],
          const Icon(Icons.calendar_today_outlined,
              size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            widget.entry.displayDate,
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 13),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.text_fields,
              size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            '${widget.entry.wordCount} words',
            style: const TextStyle(
                color: AppTheme.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.entry.displayDate,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, color: AppTheme.textSecondary),
            tooltip: 'Copy to clipboard',
            onPressed: _copyToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppTheme.textSecondary),
            tooltip: 'Delete entry',
            onPressed: _deleteEntry,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummarySection(),
            const SizedBox(height: 12),
            _buildTagsSection(),
            const SizedBox(height: 12),
            _buildTranscriptSection(),
            const SizedBox(height: 16),
            _buildMetadataRow(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
