/**
 * GBNF grammar builder for JSON Schema constrained decoding
 *
 * Converts JSON Schema (Draft 7 subset) into GBNF grammar strings
 * that can be passed to llama.cpp's grammar sampler to guarantee
 * structurally valid JSON output.
 *
 * Supports: object, string, number, integer, boolean, null, array, enum.
 * Does NOT support: $ref, oneOf, anyOf, allOf (too complex for small models).
 */

/**
 * JSON Schema type definition
 */
interface JsonSchema {
  type?: 'object' | 'string' | 'number' | 'integer' | 'boolean' | 'null' | 'array';
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  enum?: Array<string | number | boolean>;
  [key: string]: unknown;
}

/**
 * Builds GBNF grammar strings from JSON Schema definitions.
 *
 * The generated grammars constrain llama.cpp's token sampling to only
 * produce tokens that form valid JSON matching the schema. This guarantees
 * structural correctness (valid JSON, correct types) though not semantic
 * correctness (the values may be nonsensical).
 *
 * Example:
 * ```typescript
 * const grammar = GbnfBuilder.fromJsonSchema({
 *   type: 'object',
 *   properties: {
 *     name: { type: 'string' },
 *     age: { type: 'integer' },
 *   },
 *   required: ['name'],
 * });
 * // grammar is a GBNF string ready for llama_sampler_init_grammar()
 * ```
 */
export class GbnfBuilder {
  private counter = 0;
  private rules = new Map<string, string>();

  /**
   * Convert a JSON Schema to a GBNF grammar string.
   *
   * Supports a subset of JSON Schema Draft 7:
   * - `object` with `properties` and `required`
   * - `string` (with optional `enum`)
   * - `number` and `integer`
   * - `boolean`
   * - `null`
   * - `array` with `items`
   * - `enum` (string values)
   *
   * @param schema JSON Schema as an object
   * @param rootRule Name of the root grammar rule (default: "root")
   * @returns Complete GBNF grammar string
   */
  static fromJsonSchema(schema: JsonSchema, rootRule: string = 'root'): string {
    const builder = new GbnfBuilder();
    const rootRef = builder.buildRule(schema);

    // Add base rules
    builder.addBaseRules();

    // Build the grammar string with root rule first
    const lines: string[] = [];

    // Root rule aliases the generated rule
    lines.push(`${rootRule} ::= ${rootRef}`);

    // Write all generated rules
    for (const [name, rule] of builder.rules.entries()) {
      lines.push(`${name} ::= ${rule}`);
    }

    return lines.join('\n') + '\n';
  }

  /**
   * Returns a pre-built GBNF grammar that accepts any valid JSON.
   *
   * Useful when the developer wants structured JSON output without
   * a specific schema constraint.
   */
  static jsonGrammar(): string {
    return `root ::= value
value ::= object | array | string | number | ("true" | "false" | "null") ws

object ::= "{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws

array ::= "[" ws (value ("," ws value)*)? "]" ws

string ::= "\\"" ([^"\\\\\\x7F\\x00-\\x1F] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\\"" ws

number ::= ("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws

ws ::= | " " | "\\n" [ \\t]{0,20}
`;
  }

  // ---------------------------------------------------------------------------
  // Internal rule building (recursive descent)
  // ---------------------------------------------------------------------------

  private uniqueName(prefix: string): string {
    return `${prefix}${this.counter++}`;
  }

  /**
   * Build a GBNF rule for a schema node and return a reference to it.
   *
   * Returns either a rule name reference or an inline expression.
   */
  private buildRule(schema: JsonSchema): string {
    // Handle enum first (can appear with or without type)
    if (schema.enum) {
      return this.buildEnum(schema.enum);
    }

    const type = schema.type;
    if (!type) {
      // No type specified -- accept any value
      return 'value';
    }

    switch (type) {
      case 'object':
        return this.buildObject(schema);
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
        return this.buildArray(schema);
      default:
        // Unknown type -- fall back to value
        return 'value';
    }
  }

  /**
   * Build an object rule from properties and required list.
   */
  private buildObject(schema: JsonSchema): string {
    const properties = schema.properties ?? {};
    const requiredList = schema.required ?? [];

    if (Object.keys(properties).length === 0) {
      // Empty object: just {}
      const name = this.uniqueName('obj');
      this.rules.set(name, '"{" ws "}" ws');
      return name;
    }

    const requiredSet = new Set(requiredList);
    const propNames = Object.keys(properties);

    // Separate required and optional properties
    const requiredProps = propNames.filter(p => requiredSet.has(p));
    const optionalProps = propNames.filter(p => !requiredSet.has(p));

    const name = this.uniqueName('obj');

    // Build property rules
    const propRules: string[] = [];
    for (const propName of propNames) {
      const propSchema = properties[propName];
      const valueRef = this.buildRule(propSchema);
      const propRuleName = this.uniqueName('prop');
      this.rules.set(
        propRuleName,
        `"\\"${propName}\\"" ws ":" ws ${valueRef}`
      );
      propRules.push(propRuleName);
    }

    // Build the object pattern
    // Strategy: required properties in order, then optional properties
    // For simplicity, we fix the property order (required first, then optional)
    const parts: string[] = [];

    // Map prop names to their rule names
    const propRuleMap = new Map<string, string>();
    for (let i = 0; i < propNames.length; i++) {
      propRuleMap.set(propNames[i], propRules[i]);
    }

    // Build required property sequence
    for (let i = 0; i < requiredProps.length; i++) {
      if (i > 0 || parts.length > 0) {
        parts.push('"," ws');
      }
      parts.push(propRuleMap.get(requiredProps[i])!);
    }

    // Build optional property additions
    for (const optProp of optionalProps) {
      const optRuleName = this.uniqueName('opt');
      if (parts.length > 0) {
        // Optional: either comma + property or nothing
        this.rules.set(
          optRuleName,
          `("," ws ${propRuleMap.get(optProp)!})?`
        );
      } else {
        // First property and it's optional
        this.rules.set(
          optRuleName,
          `(${propRuleMap.get(optProp)!})?`
        );
      }
      parts.push(optRuleName);
    }

    const body = parts.join(' ');
    this.rules.set(name, `"{" ws ${body} "}" ws`);
    return name;
  }

  /**
   * Build an array rule from items schema.
   */
  private buildArray(schema: JsonSchema): string {
    const items = schema.items;
    const name = this.uniqueName('arr');

    if (!items) {
      // Array of any values
      this.rules.set(
        name,
        '"[" ws (value ("," ws value)*)? "]" ws'
      );
    } else {
      const itemRef = this.buildRule(items);
      this.rules.set(
        name,
        `"[" ws (${itemRef} ("," ws ${itemRef})*)? "]" ws`
      );
    }

    return name;
  }

  /**
   * Build an enum rule from a list of allowed values.
   */
  private buildEnum(values: Array<string | number | boolean>): string {
    const name = this.uniqueName('enum');
    const alternatives = values.map(v => {
      if (typeof v === 'string') {
        return `"\\"${GbnfBuilder.escapeGbnf(v)}\\"" ws`;
      }
      // Non-string enum values (numbers, booleans)
      return `"${v}" ws`;
    }).join(' | ');
    this.rules.set(name, `(${alternatives})`);
    return name;
  }

  /**
   * Add base rules shared by all grammars.
   */
  private addBaseRules(): void {
    this.rules.set('ws', '| " " | "\\n" [ \\t]{0,20}');
    this.rules.set(
      'value',
      'object-any | array-any | string | number | ("true" | "false" | "null") ws'
    );
    this.rules.set(
      'string',
      '"\\"" ([^"\\\\\\x7F\\x00-\\x1F] | "\\\\" (["\\\\/bfnrt] | "u" [0-9a-fA-F]{4}))* "\\"" ws'
    );
    this.rules.set(
      'number',
      '("-"? ([0-9] | [1-9] [0-9]{0,15})) ("." [0-9]+)? ([eE] [-+]? [0-9] [1-9]{0,15})? ws'
    );
    this.rules.set(
      'integer',
      '("-"? ([0-9] | [1-9] [0-9]{0,15})) ws'
    );
    this.rules.set(
      'boolean',
      '("true" | "false") ws'
    );
    this.rules.set(
      'object-any',
      '"{" ws (string ":" ws value ("," ws string ":" ws value)*)? "}" ws'
    );
    this.rules.set(
      'array-any',
      '"[" ws (value ("," ws value)*)? "]" ws'
    );
  }

  /**
   * Escape special characters for GBNF string literals.
   */
  static escapeGbnf(value: string): string {
    return value
      .replace(/\\/g, '\\\\')
      .replace(/"/g, '\\"');
  }
}