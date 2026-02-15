import 'package:flutter/material.dart';

/// Banner recommending professional verification for low-confidence answers.
///
/// Appears below assistant messages when [needsCloudHandoff] is true.
/// Shows a warning about consulting a healthcare professional, with an
/// optional dismiss button.
class HandoffBanner extends StatefulWidget {
  const HandoffBanner({super.key});

  @override
  State<HandoffBanner> createState() => _HandoffBannerState();
}

class _HandoffBannerState extends State<HandoffBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orange.shade900.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.orange.shade400.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_upload_outlined,
              color: Colors.orange.shade400,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This answer may benefit from professional verification',
                    style: TextStyle(
                      color: Colors.orange.shade300,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Consider consulting a healthcare professional for medical decisions.',
                    style: TextStyle(
                      color: Colors.orange.shade300.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _dismissed = true),
              child: Icon(
                Icons.close,
                color: Colors.orange.shade400.withValues(alpha: 0.6),
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
