import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/home_state.dart';
import '../theme.dart';

/// Scrollable action log showing tool calls with timestamps, arguments,
/// and success/failure indicators.
class ActionLogPanel extends StatelessWidget {
  /// Action log entries to display (newest first).
  final List<ActionLogEntry> entries;

  const ActionLogPanel({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(
          child: Text(
            'No actions yet \u2014 try saying something!',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    // Show newest first
    final reversed = entries.reversed.toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: reversed.length,
        separatorBuilder: (_, __) => const Divider(
          color: AppTheme.border,
          height: 1,
        ),
        itemBuilder: (context, index) {
          return _ActionLogTile(entry: reversed[index]);
        },
      ),
    );
  }
}

class _ActionLogTile extends StatelessWidget {
  final ActionLogEntry entry;

  const _ActionLogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(entry.timestamp);
    final argsStr = _formatArgs(entry.arguments);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 56,
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          // Success/failure indicator
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 6),
            child: Icon(
              entry.success ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: entry.success ? AppTheme.success : AppTheme.error,
            ),
          ),
          // Tool name + args
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.toolName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accent,
                  ),
                ),
                if (argsStr.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    argsStr,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatArgs(Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    try {
      return const JsonEncoder().convert(args);
    } catch (_) {
      return args.toString();
    }
  }
}
