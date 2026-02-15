import 'package:flutter/material.dart';

import '../theme.dart';
import 'confidence_badge.dart';
import 'handoff_banner.dart';

/// Chat message data with optional confidence metadata.
class ChatMsg {
  /// 'user' or 'assistant'
  final String role;

  /// Message text content.
  final String content;

  /// Average confidence for assistant messages (null for user messages).
  final double? avgConfidence;

  /// Whether cloud handoff was recommended (false for user messages).
  final bool needsHandoff;

  const ChatMsg({
    required this.role,
    required this.content,
    this.avgConfidence,
    this.needsHandoff = false,
  });
}

/// Chat bubble with confidence badge and handoff banner for assistant messages.
class MessageBubble extends StatelessWidget {
  final ChatMsg message;

  const MessageBubble({super.key, required this.message});

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Message bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isUser ? AppTheme.userBubble : AppTheme.assistantBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(_isUser ? 16 : 4),
                  bottomRight: Radius.circular(_isUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.content,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),

            // Confidence badge (assistant only)
            if (!_isUser && message.avgConfidence != null)
              ConfidenceBadge(
                confidence: message.avgConfidence!,
                needsHandoff: message.needsHandoff,
              ),

            // Handoff banner (assistant only, when recommended)
            if (!_isUser && message.needsHandoff) const HandoffBanner(),
          ],
        ),
      ),
    );
  }
}
