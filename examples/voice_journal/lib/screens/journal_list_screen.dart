import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import '../services/journal_db.dart';
import '../services/search_service.dart';
import '../theme.dart';

/// List of journal entries with search and swipe-to-delete.
class JournalListScreen extends StatefulWidget {
  final JournalDb journalDb;
  final SearchService searchService;
  final VoidCallback onRecord;
  final void Function(JournalEntry) onOpenEntry;

  const JournalListScreen({
    super.key,
    required this.journalDb,
    required this.searchService,
    required this.onRecord,
    required this.onOpenEntry,
  });

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  List<JournalEntry> _entries = [];
  List<JournalEntry> _filteredEntries = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void didUpdateWidget(covariant JournalListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh when parent rebuilds (e.g., returning from record/detail)
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final entries = await widget.journalDb.getAllEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _filteredEntries = entries;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _filteredEntries = _entries;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final matchingIds =
          await widget.searchService.search(query.trim());
      final filtered =
          _entries.where((e) => matchingIds.contains(e.id)).toList();
      if (mounted) {
        setState(() {
          _filteredEntries = filtered;
          _isSearching = false;
        });
      }
    } catch (_) {
      // Fallback to simple text search
      final lower = query.toLowerCase();
      setState(() {
        _filteredEntries = _entries
            .where((e) =>
                e.transcript.toLowerCase().contains(lower) ||
                (e.summary?.toLowerCase().contains(lower) ?? false) ||
                (e.tags?.toLowerCase().contains(lower) ?? false))
            .toList();
        _isSearching = false;
      });
    }
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    if (entry.id == null) return;
    await widget.journalDb.deleteEntry(entry.id!);
    await widget.searchService.removeEntry(entry.id!);
    _loadEntries();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        onSubmitted: _onSearch,
        onChanged: (v) {
          if (v.isEmpty) _onSearch('');
        },
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search entries...',
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          prefixIcon: const Icon(Icons.search, color: AppTheme.textTertiary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    _onSearch('');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildEntryCard(JournalEntry entry) {
    return Dismissible(
      key: Key('entry_${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.danger.withValues(alpha: 0.3),
        child: const Icon(Icons.delete, color: AppTheme.danger),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Entry?'),
            content:
                const Text('This entry will be permanently deleted.'),
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
      },
      onDismissed: (_) => _deleteEntry(entry),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onOpenEntry(entry),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date and duration
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.displayDate,
                      style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.formattedDuration.isNotEmpty)
                      Text(
                        entry.formattedDuration,
                        style: const TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Summary preview
                Text(
                  entry.shortSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),

                // Tags
                if (entry.tagList.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: entry.tagList
                        .take(5)
                        .map((tag) => Chip(
                              label: Text(tag),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_none,
            size: 64,
            color: AppTheme.accent.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'No entries yet',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap + to record your first voice journal',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Voice Journal',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSearchBar(),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(color: AppTheme.accent),
                  ),
                Expanded(
                  child: _filteredEntries.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadEntries,
                          color: AppTheme.accent,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(
                              top: 8,
                              bottom: 100,
                            ),
                            itemCount: _filteredEntries.length,
                            itemBuilder: (_, i) =>
                                _buildEntryCard(_filteredEntries[i]),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: widget.onRecord,
        backgroundColor: AppTheme.accent,
        foregroundColor: AppTheme.background,
        child: const Icon(Icons.mic),
      ),
    );
  }
}
