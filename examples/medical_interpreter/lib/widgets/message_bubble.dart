import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../theme.dart';

/// A conversation bubble showing both original and translated text.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final isProvider = message.speaker == Speaker.provider;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Align(
        alignment: isProvider ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: isProvider
                ? AppTheme.providerBubble
                : AppTheme.patientBubble,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Speaker role row
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isProvider
                        ? Icons.medical_services_outlined
                        : Icons.person_outlined,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isProvider ? 'Provider' : 'Patient',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Original language label
              Text(
                message.originalLanguage.displayName,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(height: 2),

              // Original text
              Text(
                message.originalText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),

              // Divider
              Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
              const SizedBox(height: 10),

              // Target language label
              Text(
                message.targetLanguage.displayName,
                style: TextStyle(
                  fontSize: 11,
                  color: isProvider
                      ? AppTheme.providerAccent
                      : AppTheme.patientAccent,
                ),
              ),
              const SizedBox(height: 2),

              // Translated text
              Text(
                message.translatedText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),

              // Timestamp
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
