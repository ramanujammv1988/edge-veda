import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Sub-screen demonstrating structured output capabilities:
/// - SchemaValidator: validate JSON against a schema
/// - GbnfBuilder: convert JSON schema to GBNF grammar
/// - ToolTemplate: format/parse tool calls for different template formats
class StructuredOutputScreen extends StatefulWidget {
  const StructuredOutputScreen({super.key});

  @override
  State<StructuredOutputScreen> createState() => _StructuredOutputScreenState();
}

class _StructuredOutputScreenState extends State<StructuredOutputScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // SchemaValidator state
  final _jsonController = TextEditingController(text: _exampleJson);
  final _schemaController = TextEditingController(text: _exampleSchema);
  String? _validationResult;
  bool? _isValid;

  // GbnfBuilder state
  final _gbnfSchemaController = TextEditingController(text: _exampleGbnfSchema);
  String? _gbnfOutput;

  // ToolTemplate state
  ChatTemplateFormat _selectedFormat = ChatTemplateFormat.qwen3;

  static const _exampleJson = '''{
  "name": "Alice",
  "age": 30,
  "email": "alice@example.com"
}''';

  static const _exampleSchema = '''{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "age": { "type": "integer" },
    "email": { "type": "string" }
  },
  "required": ["name", "age"]
}''';

  static const _exampleGbnfSchema = '''{
  "type": "object",
  "properties": {
    "city": { "type": "string" },
    "temperature": { "type": "number" },
    "conditions": {
      "type": "string",
      "enum": ["sunny", "cloudy", "rainy", "snowy"]
    }
  },
  "required": ["city", "temperature"]
}''';

  List<ToolDefinition> get _demoTools => [
    ToolDefinition(
      name: 'get_weather',
      description: 'Get current weather for a city',
      parameters: {
        'type': 'object',
        'properties': {
          'city': {'type': 'string', 'description': 'City name'},
          'units': {'type': 'string', 'enum': ['celsius', 'fahrenheit']},
        },
        'required': ['city'],
      },
    ),
    ToolDefinition(
      name: 'search',
      description: 'Search the web',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Search query'},
        },
        'required': ['query'],
      },
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _jsonController.dispose();
    _schemaController.dispose();
    _gbnfSchemaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Structured Output'),
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textTertiary,
          tabs: const [
            Tab(text: 'Validator'),
            Tab(text: 'GBNF'),
            Tab(text: 'Tool Tmpl'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildValidatorTab(),
          _buildGbnfTab(),
          _buildToolTemplateTab(),
        ],
      ),
    );
  }

  // ── Schema Validator Tab ─────────────────────────────────────────────

  Widget _buildValidatorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('JSON Data'),
        _buildTextField(_jsonController, 'Paste JSON here...', 5),
        const SizedBox(height: 16),
        _buildSectionHeader('JSON Schema'),
        _buildTextField(_schemaController, 'Paste schema here...', 5),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _validateSchema,
          icon: const Icon(Icons.check, size: 20),
          label: const Text('Validate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.background,
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        if (_validationResult != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_isValid == true)
                  ? AppTheme.success.withValues(alpha: 0.1)
                  : AppTheme.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_isValid == true)
                    ? AppTheme.success.withValues(alpha: 0.3)
                    : AppTheme.danger.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isValid == true ? Icons.check_circle : Icons.error,
                      color: _isValid == true ? AppTheme.success : AppTheme.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isValid == true ? 'Valid' : 'Invalid',
                      style: TextStyle(
                        color: _isValid == true ? AppTheme.success : AppTheme.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _validationResult!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _validateSchema() {
    try {
      final data = jsonDecode(_jsonController.text) as Map<String, dynamic>;
      final schema = jsonDecode(_schemaController.text) as Map<String, dynamic>;

      final result = SchemaValidator.validate(data, schema);
      setState(() {
        _isValid = result.isValid;
        _validationResult = result.isValid
            ? 'All constraints satisfied.'
            : 'Errors:\n${result.errors.join('\n')}';
      });
    } catch (e) {
      setState(() {
        _isValid = false;
        _validationResult = 'Parse error: $e';
      });
    }
  }

  // ── GBNF Builder Tab ─────────────────────────────────────────────────

  Widget _buildGbnfTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('JSON Schema Input'),
        _buildTextField(_gbnfSchemaController, 'Paste JSON schema...', 6),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _generateGbnf,
          icon: const Icon(Icons.transform, size: 20),
          label: const Text('Generate GBNF Grammar'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.background,
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        if (_gbnfOutput != null) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('Generated GBNF Grammar'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: SelectableText(
              _gbnfOutput!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _generateGbnf() {
    try {
      final schema = jsonDecode(_gbnfSchemaController.text) as Map<String, dynamic>;
      final grammar = GbnfBuilder.fromJsonSchema(schema);
      setState(() => _gbnfOutput = grammar);
    } catch (e) {
      setState(() => _gbnfOutput = 'Error: $e');
    }
  }

  // ── Tool Template Tab ────────────────────────────────────────────────

  Widget _buildToolTemplateTab() {
    final formattedPrompt = ToolTemplate.formatToolSystemPrompt(
      format: _selectedFormat,
      tools: _demoTools,
      systemPrompt: 'You are a helpful assistant with tool access.',
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('Template Format'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ChatTemplateFormat>(
              value: _selectedFormat,
              isExpanded: true,
              dropdownColor: AppTheme.surface,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textTertiary),
              items: ChatTemplateFormat.values.map((f) {
                return DropdownMenuItem(
                  value: f,
                  child: Text(f.name),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedFormat = v);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Tool Definitions'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final tool in _demoTools) ...[
                Row(
                  children: [
                    const Icon(Icons.build_outlined, color: AppTheme.accent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      tool.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 8),
                  child: Text(
                    tool.description,
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader('Formatted System Prompt'),
        Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              formattedPrompt,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared Helpers ───────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, int maxLines) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 12,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      maxLines: maxLines,
      minLines: maxLines,
    );
  }
}
