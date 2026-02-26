/**
 * JSON Schema validation for structured output.
 *
 * Validates JSON data against JSON Schema Draft 7 schemas. Used by the tool
 * calling system to validate model-generated arguments against tool parameter schemas.
 *
 * Note: This implementation provides basic validation for common schema features.
 * For production use, consider integrating a full-featured validator like Ajv.
 */

/**
 * Result of validating JSON data against a JSON Schema.
 */
export class SchemaValidationResult {
  /** Whether the data conforms to the schema. */
  readonly isValid: boolean;

  /** Validation error messages (empty if valid). */
  readonly errors: string[];

  /** The validated data if valid, null otherwise. */
  readonly validatedData: Record<string, unknown> | null;

  private constructor(
    isValid: boolean,
    errors: string[],
    validatedData: Record<string, unknown> | null = null
  ) {
    this.isValid = isValid;
    this.errors = errors;
    this.validatedData = validatedData;
  }

  /** Create a successful validation result. */
  static valid(data: Record<string, unknown>): SchemaValidationResult {
    return new SchemaValidationResult(true, [], data);
  }

  /** Create a failed validation result. */
  static invalid(errors: string[]): SchemaValidationResult {
    return new SchemaValidationResult(false, errors, null);
  }

  toString(): string {
    return this.isValid
      ? 'SchemaValidationResult(valid)'
      : `SchemaValidationResult(invalid, ${this.errors.length} errors)`;
  }
}

/**
 * JSON Schema definition
 */
interface JsonSchema {
  type?: 'object' | 'string' | 'number' | 'integer' | 'boolean' | 'null' | 'array';
  properties?: Record<string, JsonSchema>;
  required?: string[];
  items?: JsonSchema;
  enum?: Array<string | number | boolean>;
  minimum?: number;
  maximum?: number;
  minLength?: number;
  maxLength?: number;
  pattern?: string;
  [key: string]: unknown;
}

/**
 * Validates JSON data against JSON Schema Draft 7 schemas.
 *
 * Provides basic validation for common schema features. For production
 * use with complex schemas, consider integrating a full-featured validator.
 *
 * Example:
 * ```typescript
 * const schema = {
 *   type: 'object',
 *   properties: {
 *     location: { type: 'string' },
 *   },
 *   required: ['location'],
 * };
 * const result = SchemaValidator.validate({ location: 'Tokyo' }, schema);
 * console.log(result.isValid); // true
 * ```
 */
export class SchemaValidator {
  // Prevent instantiation -- all methods are static.
  private constructor() {}

  /**
   * Validate data against a JSON Schema Draft 7 schema.
   *
   * Returns a SchemaValidationResult with validation outcome.
   * If the schema itself is malformed, returns an invalid result
   * with an error describing the schema issue.
   */
  static validate(
    data: unknown,
    schema: JsonSchema
  ): SchemaValidationResult {
    try {
      const errors: string[] = [];
      this.validateValue(data, schema, '', errors);

      if (errors.length === 0) {
        return SchemaValidationResult.valid(data as Record<string, unknown>);
      }

      return SchemaValidationResult.invalid(errors);
    } catch (e) {
      return SchemaValidationResult.invalid([
        `Schema validation error: ${e instanceof Error ? e.message : String(e)}`,
      ]);
    }
  }

  /**
   * Internal recursive validation method
   */
  private static validateValue(
    value: unknown,
    schema: JsonSchema,
    path: string,
    errors: string[]
  ): void {
    // Handle enum validation first (can appear with or without type)
    if (schema.enum) {
      if (!schema.enum.includes(value as string | number | boolean)) {
        errors.push(
          `${path || 'root'}: value must be one of [${schema.enum.join(', ')}]`
        );
      }
      return;
    }

    const type = schema.type;
    if (!type) {
      // No type constraint -- accept any value
      return;
    }

    // Type validation
    const actualType = this.getJsonType(value);
    if (actualType !== type) {
      errors.push(`${path || 'root'}: expected type '${type}' but got '${actualType}'`);
      return;
    }

    // Type-specific validation
    switch (type) {
      case 'object':
        this.validateObject(value as Record<string, unknown>, schema, path, errors);
        break;
      case 'array':
        this.validateArray(value as unknown[], schema, path, errors);
        break;
      case 'string':
        this.validateString(value as string, schema, path, errors);
        break;
      case 'number':
      case 'integer':
        this.validateNumber(value as number, schema, path, errors);
        break;
    }
  }

  /**
   * Get the JSON Schema type of a value
   */
  private static getJsonType(value: unknown): string {
    if (value === null) return 'null';
    if (Array.isArray(value)) return 'array';
    
    const jsType = typeof value;
    if (jsType === 'object') return 'object';
    if (jsType === 'boolean') return 'boolean';
    if (jsType === 'string') return 'string';
    if (jsType === 'number') {
      return Number.isInteger(value) ? 'integer' : 'number';
    }
    
    return jsType;
  }

  /**
   * Validate an object against schema
   */
  private static validateObject(
    obj: Record<string, unknown>,
    schema: JsonSchema,
    path: string,
    errors: string[]
  ): void {
    const properties = schema.properties ?? {};
    const required = schema.required ?? [];

    // Check required properties
    for (const reqProp of required) {
      if (!(reqProp in obj)) {
        errors.push(`${path || 'root'}: missing required property '${reqProp}'`);
      }
    }

    // Validate each property
    for (const [propName, propValue] of Object.entries(obj)) {
      const propSchema = properties[propName];
      if (propSchema) {
        const propPath = path ? `${path}.${propName}` : propName;
        this.validateValue(propValue, propSchema, propPath, errors);
      }
      // Note: We don't error on additional properties (follows common lenient behavior)
    }
  }

  /**
   * Validate an array against schema
   */
  private static validateArray(
    arr: unknown[],
    schema: JsonSchema,
    path: string,
    errors: string[]
  ): void {
    const itemsSchema = schema.items;
    if (!itemsSchema) {
      return; // No items constraint
    }

    // Validate each item
    for (let i = 0; i < arr.length; i++) {
      const itemPath = `${path}[${i}]`;
      this.validateValue(arr[i], itemsSchema, itemPath, errors);
    }
  }

  /**
   * Validate a string against schema
   */
  private static validateString(
    str: string,
    schema: JsonSchema,
    path: string,
    errors: string[]
  ): void {
    if (schema.minLength !== undefined && str.length < schema.minLength) {
      errors.push(
        `${path || 'root'}: string length ${str.length} is less than minimum ${schema.minLength}`
      );
    }

    if (schema.maxLength !== undefined && str.length > schema.maxLength) {
      errors.push(
        `${path || 'root'}: string length ${str.length} exceeds maximum ${schema.maxLength}`
      );
    }

    if (schema.pattern !== undefined) {
      const regex = new RegExp(schema.pattern);
      if (!regex.test(str)) {
        errors.push(
          `${path || 'root'}: string does not match pattern '${schema.pattern}'`
        );
      }
    }
  }

  /**
   * Validate a number against schema
   */
  private static validateNumber(
    num: number,
    schema: JsonSchema,
    path: string,
    errors: string[]
  ): void {
    if (schema.type === 'integer' && !Number.isInteger(num)) {
      errors.push(`${path || 'root'}: expected integer but got ${num}`);
    }

    if (schema.minimum !== undefined && num < schema.minimum) {
      errors.push(
        `${path || 'root'}: value ${num} is less than minimum ${schema.minimum}`
      );
    }

    if (schema.maximum !== undefined && num > schema.maximum) {
      errors.push(
        `${path || 'root'}: value ${num} exceeds maximum ${schema.maximum}`
      );
    }
  }
}