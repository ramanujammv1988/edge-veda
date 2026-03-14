/// GBNF grammar builder for JSON Schema constrained decoding
///
/// Converts JSON Schema (Draft 7 subset) into GBNF grammar strings
/// that can be passed to llama.cpp's grammar sampler to guarantee
/// structurally valid JSON output.
///
/// Supports: object, string, number, integer, boolean, null, array, enum,
/// \$ref resolution, and grammar rule budget enforcement.
library;

/// Result of grammar generation, including budget status.
class GbnfResult {
  /// The generated GBNF grammar string.
  final String grammar;

  /// Whether the rule budget was exceeded during generation.
  ///
  /// When true, some sub-schemas were degraded to the generic `value` rule
  /// (any valid JSON). Post-generation schema validation can still catch
  /// semantic violations.
  final bool budgetExceeded;

  /// Creates a grammar generation result.
  const GbnfResult({required this.grammar, required this.budgetExceeded});
}

/// Builds GBNF grammar strings from JSON Schema definitions.
///
/// The generated grammars constrain llama.cpp's token sampling to only
/// produce tokens that form valid JSON matching the schema. This guarantees
/// structural correctness (valid JSON, correct types) though not semantic
/// correctness (the values may be nonsensical).
///
/// Example:
/// ```dart
/// final grammar = GbnfBuilder.fromJsonSchema({
///   'type': 'object',
///   'properties': {
///     'name': {'type': 'string'},
///     'age': {'type': 'integer'},
///   },
///   'required': ['name'],
/// });
/// // grammar is a GBNF string ready for llama_sampler_init_grammar()
/// ```
class GbnfBuilder {
  int _counter = 0;
  final _rules = <String, String>{};

  /// The root schema, stored for $ref resolution.
  late final Map<String, dynamic> _rootSchema;

  /// Set of $ref pointers currently being resolved (cycle detection).
  final _resolving = <String>{};

  /// Cache of already-resolved $ref pointers to their rule names.
  final _refCache = <String, String>{};

  /// Maximum number of rules before budget degradation.
  final int _maxRules;

  /// Whether the rule budget was exceeded during generation.
  bool _budgetExceeded = false;

  /// Creates a builder with optional rule budget.
  GbnfBuilder({int maxRules = 500}) : _maxRules = maxRules;

  /// Convert a JSON Schema to a GBNF grammar string.
  ///
  /// Supports a subset of JSON Schema Draft 7:
  /// - `object` with `properties` and `required`
  /// - `string` (with optional `enum`)
  /// - `number` and `integer`
  /// - `boolean`
  /// - `null`
  /// - `array` with `items`
  /// - `enum` (string values)
  /// - `$ref` resolution (with cycle detection)
  ///
  /// [schema] is a JSON Schema as a Dart map.
  /// [rootRule] is the name of the root grammar rule (default: "root").
  /// [maxRules] is the maximum number of grammar rules before budget
  /// degradation (default: 500).
  ///
  /// Returns a complete GBNF grammar string.
  static String fromJsonSchema(
    Map<String, dynamic> schema, {
    String rootRule = 'root',
    int maxRules = 500,
  }) {
    return build(schema, rootRule: rootRule, maxRules: maxRules).grammar;
  }

  /// Build a GBNF grammar from a JSON Schema, returning a [GbnfResult]
  /// that includes both the grammar string and budget status.
  ///
  /// [schema] is a JSON Schema as a Dart map.
  /// [rootRule] is the name of the root grammar rule (default: "root").
  /// [maxRules] is the maximum number of grammar rules before budget
  /// degradation (default: 500).
  static GbnfResult build(
    Map<String, dynamic> schema, {
    String rootRule = 'root',
    int maxRules = 500,
  }) {
    final builder = GbnfBuilder(maxRules: maxRules);
    builder._rootSchema = schema;
    final rootRef = builder._buildRule(schema);

    // Add base rules
    builder._addBaseRules();

    // Build the grammar string with root rule first
    final buffer = StringBuffer();

    // Root rule aliases the generated rule
    buffer.writeln('$rootRule ::= $rootRef');

    // Write all generated rules
    for (final entry in builder._rules.entries) {
      buffer.writeln('${entry.key} ::= ${entry.value}');
    }

    return GbnfResult(
      grammar: buffer.toString(),
      budgetExceeded: builder._budgetExceeded,
    );
  }

  /// Returns a pre-built GBNF grammar that accepts any valid JSON.
  ///
  /// Useful when the developer wants structured JSON output without
  /// a specific schema constraint.
  static String jsonGrammar() => r'''root ::= value
value ::= object | array | string | number | ("true" | "false" | "null") ws

object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws

array ::= "[" ws (value ("," ws value)*)? "]" ws

string ::= "\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\"" ws

number ::= ("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws

ws ::= | " " | "\n" [ \t]{0,20}
''';

  // ---------------------------------------------------------------------------
  // Internal rule building (recursive descent)
  // ---------------------------------------------------------------------------

  String _uniqueName(String prefix) => '$prefix${_counter++}';

  /// Build a GBNF rule for a schema node and return a reference to it.
  ///
  /// Returns either a rule name reference or an inline expression.
  String _buildRule(Map<String, dynamic> schema) {
    // Budget check: if we've hit the rule limit, degrade to 'value'
    if (_rules.length >= _maxRules) {
      _budgetExceeded = true;
      return 'value';
    }

    // Handle $ref before anything else
    if (schema.containsKey(r'$ref')) {
      return _resolveRef(schema[r'$ref'] as String);
    }

    // Handle enum (can appear with or without type)
    if (schema.containsKey('enum')) {
      return _buildEnum(schema['enum'] as List);
    }

    final type = schema['type'];
    if (type == null) {
      // No type specified -- accept any value
      return 'value';
    }

    switch (type) {
      case 'object':
        return _buildObject(schema);
      case 'string':
        return 'string ws';
      case 'number':
        return 'number ws';
      case 'integer':
        return 'integer ws';
      case 'boolean':
        return 'boolean ws';
      case 'null':
        return '"null" ws';
      case 'array':
        return _buildArray(schema);
      default:
        // Unknown type -- fall back to value
        return 'value';
    }
  }

  /// Resolve a $ref pointer to its target sub-schema and return the rule name.
  ///
  /// Navigates JSON pointer path segments from the root schema.
  /// Supports both `#/definitions/X` and `#/$defs/X` styles.
  /// Detects cycles via [_resolving] set to prevent infinite recursion.
  /// Caches resolved refs via [_refCache] to avoid duplicate rule generation.
  String _resolveRef(String ref) {
    // Return cached rule name if already resolved
    if (_refCache.containsKey(ref)) {
      return _refCache[ref]!;
    }

    // Cycle detection: if this ref is currently being resolved, return the
    // rule name that will be defined when resolution completes
    if (_resolving.contains(ref)) {
      // Generate a stable rule name for this ref
      final segments = ref.split('/').where((s) => s != '#' && s.isNotEmpty);
      final ruleName = 'ref-${segments.join('-')}';
      return ruleName;
    }

    // Navigate the JSON pointer to find the target sub-schema
    final target = _navigatePointer(ref);
    if (target == null) {
      // Missing definition -- fall back to value
      return 'value';
    }

    // Generate a stable rule name for this ref
    final segments = ref.split('/').where((s) => s != '#' && s.isNotEmpty);
    final ruleName = 'ref-${segments.join('-')}';

    // Mark as resolving (cycle detection)
    _resolving.add(ref);
    _refCache[ref] = ruleName;

    // Build the rule for the target schema
    final targetRef = _buildRule(target);

    // Create the named rule mapping ref name to target
    _rules[ruleName] = targetRef;

    // Done resolving
    _resolving.remove(ref);

    return ruleName;
  }

  /// Navigate a JSON pointer (e.g., "#/definitions/Address") within the
  /// root schema and return the target sub-schema, or null if not found.
  Map<String, dynamic>? _navigatePointer(String pointer) {
    // Split on '/' and skip the '#' prefix
    final segments =
        pointer.split('/').where((s) => s != '#' && s.isNotEmpty).toList();

    dynamic current = _rootSchema;
    for (final segment in segments) {
      if (current is Map<String, dynamic> && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }

    if (current is Map<String, dynamic>) {
      return current;
    }
    return null;
  }

  /// Build an object rule from properties and required list.
  String _buildObject(Map<String, dynamic> schema) {
    final properties = schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredList = (schema['required'] as List?)?.cast<String>() ?? [];

    if (properties.isEmpty) {
      // Empty object: just {}
      final name = _uniqueName('obj');
      _rules[name] = '"{" ws "}" ws';
      return name;
    }

    final requiredSet = requiredList.toSet();
    final propNames = properties.keys.toList();

    // Separate required and optional properties
    final requiredProps =
        propNames.where((p) => requiredSet.contains(p)).toList();
    final optionalProps =
        propNames.where((p) => !requiredSet.contains(p)).toList();

    final name = _uniqueName('obj');

    // Build property rules
    final propRules = <String>[];
    for (final propName in propNames) {
      final propSchema = properties[propName] as Map<String, dynamic>;
      final valueRef = _buildRule(propSchema);
      final propRuleName = _uniqueName('prop');
      _rules[propRuleName] = '"\\"$propName\\"" ws ":" ws $valueRef';
      propRules.add(propRuleName);
    }

    // Build the object pattern
    // Strategy: required properties in order, then optional properties
    // For simplicity, we fix the property order (required first, then optional)
    final parts = <String>[];

    // Map prop names to their rule names
    final propRuleMap = <String, String>{};
    for (var i = 0; i < propNames.length; i++) {
      propRuleMap[propNames[i]] = propRules[i];
    }

    // Build required property sequence
    for (var i = 0; i < requiredProps.length; i++) {
      if (i > 0 || parts.isNotEmpty) {
        parts.add('"," ws');
      }
      parts.add(propRuleMap[requiredProps[i]]!);
    }

    // Build optional property additions
    for (final optProp in optionalProps) {
      final optRuleName = _uniqueName('opt');
      if (parts.isNotEmpty) {
        // Optional: either comma + property or nothing
        _rules[optRuleName] = '("," ws ${propRuleMap[optProp]!})?';
      } else {
        // First property and it's optional
        _rules[optRuleName] = '(${propRuleMap[optProp]!})?';
      }
      parts.add(optRuleName);
    }

    final body = parts.join(' ');
    _rules[name] = '"{" ws $body "}" ws';
    return name;
  }

  /// Build an array rule from items schema.
  String _buildArray(Map<String, dynamic> schema) {
    final items = schema['items'] as Map<String, dynamic>?;
    final name = _uniqueName('arr');

    if (items == null) {
      // Array of any values
      _rules[name] = '"[" ws (value ("," ws value)*)? "]" ws';
    } else {
      final itemRef = _buildRule(items);
      _rules[name] = '"[" ws ($itemRef ("," ws $itemRef)*)? "]" ws';
    }

    return name;
  }

  /// Build an enum rule from a list of allowed values.
  String _buildEnum(List values) {
    final name = _uniqueName('enum');
    final alternatives = values
        .map((v) {
          if (v is String) {
            return '"\\"${_escapeGbnf(v)}\\"" ws';
          }
          // Non-string enum values (numbers, booleans)
          return '"$v" ws';
        })
        .join(' | ');
    _rules[name] = '($alternatives)';
    return name;
  }

  /// Add base rules shared by all grammars.
  void _addBaseRules() {
    _rules['ws'] = r'| " " | "\n" [ \t]{0,20}';
    _rules['value'] =
        r'object-any | array-any | string | number | ("true" | "false" | "null") ws';
    _rules['string'] =
        r'''"\"" ([^"\\\x7F\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\"" ws''';
    _rules['number'] =
        r'("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws';
    _rules['integer'] = r'("-"? ([0-9] | [1-9] [0-9]{0,15})) ws';
    _rules['boolean'] = r'("true" | "false") ws';
    _rules['object-any'] =
        r'"{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws';
    _rules['array-any'] = r'"[" ws (value ("," ws value)*)? "]" ws';
  }

  /// Escape special characters for GBNF string literals.
  static String _escapeGbnf(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  }
}
