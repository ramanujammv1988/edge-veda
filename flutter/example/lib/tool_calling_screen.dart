import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Sub-screen demonstrating advanced tool calling features:
/// - ToolPriority: required vs optional tool filtering
/// - ToolRegistry.forBudgetLevel(): QoS-based tool filtering
class ToolCallingScreen extends StatefulWidget {
  const ToolCallingScreen({super.key});

  @override
  State<ToolCallingScreen> createState() => _ToolCallingScreenState();
}

class _ToolCallingScreenState extends State<ToolCallingScreen> {
  QoSLevel _selectedLevel = QoSLevel.full;
  bool _showRequiredOnly = false;

  List<ToolDefinition> get _demoTools => [
    ToolDefinition(
      name: 'get_time',
      description: 'Get current date and time for a location',
      parameters: {
        'type': 'object',
        'properties': {
          'location': {'type': 'string', 'description': 'City name'},
        },
        'required': ['location'],
      },
      priority: ToolPriority.required,
    ),
    ToolDefinition(
      name: 'calculate',
      description: 'Perform a math calculation',
      parameters: {
        'type': 'object',
        'properties': {
          'expression': {'type': 'string', 'description': 'Math expression'},
        },
        'required': ['expression'],
      },
      priority: ToolPriority.required,
    ),
    ToolDefinition(
      name: 'search_web',
      description: 'Search the web for information',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query'},
        },
        'required': ['query'],
      },
      priority: ToolPriority.optional,
    ),
    ToolDefinition(
      name: 'translate',
      description: 'Translate text between languages',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
          'to': {'type': 'string'},
        },
        'required': ['text', 'to'],
      },
      priority: ToolPriority.optional,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final registry = ToolRegistry(_demoTools);
    final filteredByBudget = registry.forBudgetLevel(_selectedLevel);
    final displayTools = _showRequiredOnly ? registry.requiredTools : registry.tools;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Tool Calling'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          // ── Tool Priority Section ────────────────────────────────────
          _buildSectionHeader('Tool Priority'),
          _buildCard(
            child: Column(
              children: [
                // Filter toggle
                SwitchListTile(
                  title: const Text(
                    'Show Required Only',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  ),
                  subtitle: Text(
                    _showRequiredOnly
                        ? '${registry.requiredTools.length} required tools'
                        : '${registry.tools.length} total tools',
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                  value: _showRequiredOnly,
                  onChanged: (v) => setState(() => _showRequiredOnly = v),
                  activeTrackColor: AppTheme.accent,
                ),
                const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                // Tool list
                for (int i = 0; i < displayTools.length; i++) ...[
                  _buildToolRow(displayTools[i]),
                  if (i < displayTools.length - 1)
                    const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── forBudgetLevel Section ───────────────────────────────────
          _buildSectionHeader('QoS Budget Level'),
          _buildCard(
            child: Column(
              children: [
                // QoS level selector
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select QoS Level to see which tools are available:',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: QoSLevel.values.map((level) {
                          final isSelected = level == _selectedLevel;
                          return ChoiceChip(
                            label: Text(level.name),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _selectedLevel = level),
                            selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                            backgroundColor: AppTheme.surfaceVariant,
                            labelStyle: TextStyle(
                              color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: isSelected ? AppTheme.accent : AppTheme.border,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                // Filtered tools display
                if (filteredByBudget.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.block, color: AppTheme.textTertiary, size: 20),
                        SizedBox(width: 12),
                        Text(
                          'No tools available at this budget level',
                          style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  for (int i = 0; i < filteredByBudget.length; i++) ...[
                    _buildToolRow(filteredByBudget[i]),
                    if (i < filteredByBudget.length - 1)
                      const Divider(color: AppTheme.border, indent: 16, endIndent: 16, height: 1),
                  ],
                // Summary
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _budgetExplanation(_selectedLevel),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(ToolDefinition tool) {
    final isRequired = tool.priority == ToolPriority.required;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.build_outlined,
            color: isRequired ? AppTheme.accent : AppTheme.textTertiary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  tool.description,
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isRequired
                  ? AppTheme.accent.withValues(alpha: 0.15)
                  : AppTheme.textTertiary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              isRequired ? 'Required' : 'Optional',
              style: TextStyle(
                color: isRequired ? AppTheme.accent : AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _budgetExplanation(QoSLevel level) {
    return switch (level) {
      QoSLevel.full => 'Full: All tools available. Max inference quality with complete tool access.',
      QoSLevel.reduced => 'Reduced: Only required tools. Optional tools removed to lower token/context cost.',
      QoSLevel.minimal => 'Minimal: No tools available. Minimum viable inference to conserve resources.',
      QoSLevel.paused => 'Paused: Inference stopped. No tools or generation -- battery/thermal protection mode.',
    };
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}
