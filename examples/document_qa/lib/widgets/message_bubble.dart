import 'package:flutter/material.dart';

import '../theme.dart';

/// Chat message bubble for Document Q&A conversations.
///
/// User messages are right-aligned with blue accent background.
/// Assistant messages are left-aligned with dark surface background.
class MessageBubble extends StatelessWidget {
  /// The message text content.
  final String text;

  /// Whether this is a user message (true) or assistant message (false).
  final bool isUser;

  /// Whether to show the "Based on your document" source indicator.
  /// Only applicable for assistant messages.
  final bool showSource;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.showSource = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const Padding(
              padding: EdgeInsets.only(top: 4, right: 8),
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: AppTheme.accent,
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUser
                        ? AppTheme.userBubble
                        : AppTheme.assistantBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isUser
                          ? const Radius.circular(16)
                          : Radius.zero,
                      bottomRight: isUser
                          ? Radius.zero
                          : const Radius.circular(16),
                    ),
                  ),
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
                if (showSource && !isUser) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Based on your document',
                    style: TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
