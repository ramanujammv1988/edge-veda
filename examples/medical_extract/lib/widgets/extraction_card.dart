import 'package:flutter/material.dart';
import '../theme.dart';

/// Displays extracted prescription data as a structured card.
class PrescriptionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const PrescriptionCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.medication, color: AppTheme.accent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Prescription',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 24),
            _field('Drug Name', data['drug_name']),
            _field('Dosage', data['dosage']),
            _field('Frequency', data['frequency']),
            _field('Prescriber', data['prescriber']),
            _field('Date', data['date']),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? '—',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays extracted lab report data as a structured card.
class LabReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const LabReportCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final flag = (data['flag'] ?? '').toString().toLowerCase();
    final flagColor = flag == 'high'
        ? AppTheme.danger
        : flag == 'low'
            ? AppTheme.warning
            : AppTheme.success;

    return Card(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: flagColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.biotech, color: flagColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data['test_name']?.toString() ?? 'Lab Test',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (flag.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: flagColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      flag.toUpperCase(),
                      style: TextStyle(
                        color: flagColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(color: AppTheme.border, height: 24),
            _field('Value', '${data['value'] ?? '—'} ${data['unit'] ?? ''}'),
            _field('Reference', data['reference_range']),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value?.toString() ?? '—',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
