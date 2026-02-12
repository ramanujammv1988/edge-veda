/// GBNF grammar builder for JSON Schema constrained decoding
///
/// Converts JSON Schema (Draft 7 subset) into GBNF grammar strings
/// that can be passed to llama.cpp's grammar sampler to guarantee
/// structurally valid JSON output.
///
/// Supports: object, string, number, integer, boolean, null, array, enum.
/// Does NOT support: \$ref, oneOf, anyOf, allOf (too complex for small models).
library;

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
  ///
  /// [schema] is a JSON Schema as a Dart map.
  /// [rootRule] is the name of the root grammar rule (default: "root").
  ///
  /// Returns a complete GBNF grammar string.
  static String fromJsonSchema(
    Map<String, dynamic> schema, {
    String rootRule = 'root',
  }) {
    final builder = GbnfBuilder();
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

    return buffer.toString();
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
    // Handle enum first (can appear with or without type)
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

  /// Build an object rule from properties and required list.
  String _buildObject(Map<String, dynamic> schema) {
    final properties =
        schema['properties'] as Map<String, dynamic>? ?? {};
    final requiredList =
        (schema['required'] as List?)?.cast<String>() ?? [];

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
      _rules[propRuleName] =
          '"\\"$propName\\"" ws ":" ws $valueRef';
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
      _rules[name] =
          '"[" ws (value ("," ws value)*)? "]" ws';
    } else {
      final itemRef = _buildRule(items);
      _rules[name] =
          '"[" ws ($itemRef ("," ws $itemRef)*)? "]" ws';
    }

    return name;
  }

  /// Build an enum rule from a list of allowed values.
  String _buildEnum(List values) {
    final name = _uniqueName('enum');
    final alternatives = values.map((v) {
      if (v is String) {
        return '"\\"${_escapeGbnf(v)}\\"" ws';
      }
      // Non-string enum values (numbers, booleans)
      return '"$v" ws';
    }).join(' | ');
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
    _rules['integer'] =
        r'("-"? ([0-9] | [1-9] [0-9]{0,15})) ws';
    _rules['boolean'] =
        r'("true" | "false") ws';
    _rules['object-any'] =
        r'"{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws';
    _rules['array-any'] =
        r'"[" ws (value ("," ws value)*)? "]" ws';
  }

  /// Escape special characters for GBNF string literals.
  static String _escapeGbnf(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
  }
}
