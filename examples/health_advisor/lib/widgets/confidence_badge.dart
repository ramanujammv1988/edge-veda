import 'package:flutter/material.dart';

import '../theme.dart';

/// Compact badge showing the confidence score of an assistant response.
///
/// Displays a shield icon and "XX% confident" text, color-coded:
///   - Green  (>70%): high confidence
///   - Orange (40-70%): medium confidence
///   - Red    (<40%): low confidence
class ConfidenceBadge extends StatelessWidget {
  /// Confidence score in 0.0-1.0 range.
  final double confidence;

  /// Whether cloud handoff was recommended.
  final bool needsHandoff;

  const ConfidenceBadge({
    super.key,
    required this.confidence,
    this.needsHandoff = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.confidenceColor(confidence);
    final percent = (confidence * 100).toInt();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            '$percent% confident',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
