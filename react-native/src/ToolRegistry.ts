/**
 * Tool registry for managing function calling tool collections.
 *
 * ToolRegistry holds a validated set of ToolDefinitions and provides
 * budget-aware filtering via forBudgetLevel to degrade tool availability
 * under resource pressure.
 */

import { ConfigurationException, QoSLevel } from './types';

/**
 * Priority level for a tool in the registry.
 *
 * Used by ToolRegistry.forBudgetLevel to degrade tool availability
 * under resource pressure. Required tools are kept longer than optional ones.
 */
export enum ToolPriority {
  /** Tool is essential -- kept available under reduced QoS */
  REQUIRED = 'required',
  /** Tool is nice-to-have -- dropped first under resource pressure */
  OPTIONAL = 'optional',
}

/**
 * Name validation pattern for tool function names.
 * Allows alphanumeric characters and underscores, starting with a letter
 * or underscore. Maximum 64 characters.
 */
const TOOL_NAME_PATTERN = /^[a-zA-Z_][a-zA-Z0-9_]{0,63}$/;

/**
 * Immutable definition of a tool that a model can invoke.
 *
 * Each tool has a unique name, human-readable description, and a
 * JSON Schema parameters object describing the expected arguments.
 *
 * @example
 * ```typescript
 * const weatherTool = new ToolDefinition({
 *   name: 'get_weather',
 *   description: 'Get current weather for a location',
 *   parameters: {
 *     type: 'object',
 *     properties: {
 *       location: { type: 'string', description: 'City name' },
 *       unit: { type: 'string', enum: ['celsius', 'fahrenheit'] },
 *     },
 *     required: ['location'],
 *   },
 * });
 * ```
 */
export class ToolDefinition {
  /** Tool function name (alphanumeric + underscores, 1-64 chars) */
  readonly name: string;

  /** Human-readable description of what the tool does, shown to the model */
  readonly description: string;

  /** JSON Schema object describing the tool's parameters */
  readonly parameters: Record<string, any>;

  /** Priority for budget-aware degradation */
  readonly priority: ToolPriority;

  /**
   * Create a tool definition with validation.
   *
   * @throws {ConfigurationException} if:
   * - name does not match `^[a-zA-Z_][a-zA-Z0-9_]{0,63}$`
   * - description is empty
   * - parameters does not have `'type': 'object'`
   */
  constructor(config: {
    name: string;
    description: string;
    parameters: Record<string, any>;
    priority?: ToolPriority;
  }) {
    if (!TOOL_NAME_PATTERN.test(config.name)) {
      throw new ConfigurationException(
        `Invalid tool name: "${config.name}"`,
        'Tool names must match ^[a-zA-Z_][a-zA-Z0-9_]{0,63}$ ' +
          '(alphanumeric + underscores, 1-64 chars, starting with letter or underscore)'
      );
    }
    if (!config.description || config.description.trim().length === 0) {
      throw new ConfigurationException(
        'Tool description cannot be empty',
        `Tool "${config.name}" must have a non-empty description`
      );
    }
    if (config.parameters.type !== 'object') {
      throw new ConfigurationException(
        'Tool parameters must be a JSON Schema object',
        `Tool "${config.name}" parameters must have 'type': 'object' at the top level`
      );
    }

    this.name = config.name;
    this.description = config.description;
    this.parameters = config.parameters;
    this.priority = config.priority ?? ToolPriority.REQUIRED;
  }

  /**
   * Serialize to Hermes/Qwen3 function calling format.
   */
  toFunctionJson(): Record<string, any> {
    return {
      type: 'function',
      function: {
        name: this.name,
        description: this.description,
        parameters: this.parameters,
      },
    };
  }

  /**
   * Serialize to Gemma3/FunctionGemma tool calling format.
   */
  toToolJson(): Record<string, any> {
    return {
      name: this.name,
      description: this.description,
      parameters: this.parameters,
    };
  }

  /** Serialize to JSON string (Hermes format) for prompt injection */
  toFunctionJsonString(): string {
    return JSON.stringify(this.toFunctionJson());
  }

  toString(): string {
    return `ToolDefinition(${this.name}, priority=${this.priority})`;
  }
}

/**
 * A parsed tool call extracted from model output.
 *
 * Contains the tool name and parsed arguments that the model
 * wants to invoke. The id is auto-generated for tracking.
 */
export class ToolCall {
  /** Unique identifier for this tool call (base-36 timestamp) */
  readonly id: string;

  /** Name of the tool function to invoke */
  readonly name: string;

  /** Parsed arguments from the model output */
  readonly arguments: Record<string, any>;

  /**
   * Create a tool call with an auto-generated ID.
   */
  constructor(config: { name: string; arguments: Record<string, any> }) {
    this.id = Date.now().toString(36);
    this.name = config.name;
    this.arguments = config.arguments;
  }

  /**
   * Create a tool call with an explicit ID (for deserialization).
   */
  static withId(config: {
    id: string;
    name: string;
    arguments: Record<string, any>;
  }): ToolCall {
    const call = Object.create(ToolCall.prototype);
    call.id = config.id;
    call.name = config.name;
    call.arguments = config.arguments;
    return call;
  }

  toString(): string {
    return `ToolCall(${this.id}, ${this.name}, ${JSON.stringify(this.arguments)})`;
  }
}

/**
 * Result of executing a tool call, provided by the developer.
 *
 * Create via ToolResult.success or ToolResult.failure factories.
 */
export class ToolResult {
  /** References the ToolCall.id this result responds to */
  readonly toolCallId: string;

  /** Successful result data, or null if the tool failed */
  readonly data: Record<string, any> | null;

  /** Error message if the tool execution failed, or null on success */
  readonly error: string | null;

  /** Whether this result represents a failure */
  get isError(): boolean {
    return this.error !== null;
  }

  private constructor(config: {
    toolCallId: string;
    data?: Record<string, any>;
    error?: string;
  }) {
    this.toolCallId = config.toolCallId;
    this.data = config.data ?? null;
    this.error = config.error ?? null;
  }

  /** Create a successful tool result */
  static success(config: {
    toolCallId: string;
    data: Record<string, any>;
  }): ToolResult {
    return new ToolResult({
      toolCallId: config.toolCallId,
      data: config.data,
    });
  }

  /** Create a failed tool result */
  static failure(config: { toolCallId: string; error: string }): ToolResult {
    return new ToolResult({
      toolCallId: config.toolCallId,
      error: config.error,
    });
  }

  toString(): string {
    return this.isError
      ? `ToolResult.failure(${this.toolCallId}, ${this.error})`
      : `ToolResult.success(${this.toolCallId}, ${JSON.stringify(this.data)})`;
  }
}

/**
 * Thrown when model output cannot be parsed as a valid tool call.
 *
 * Contains the rawOutput that failed to parse for debugging.
 */
export class ToolCallParseException extends Error {
  /** The raw model output that could not be parsed as a tool call */
  readonly rawOutput: string;

  constructor(message: string, rawOutput: string, details?: string) {
    const truncated =
      rawOutput.length > 100 ? `${rawOutput.substring(0, 100)}...` : rawOutput;
    super(
      `ToolCallParseException: ${message} (raw: "${truncated}")${
        details ? `\n${details}` : ''
      }`
    );
    this.name = 'ToolCallParseException';
    this.rawOutput = rawOutput;
  }
}

/**
 * Manages a collection of ToolDefinitions with budget-aware filtering.
 *
 * Enforces a maximum tool count (default 5) to prevent context window
 * exhaustion on small models. Tools are categorized by ToolPriority
 * for graceful degradation under resource pressure.
 *
 * @example
 * ```typescript
 * const registry = new ToolRegistry([weatherTool, searchTool, calcTool]);
 * console.log(registry.tools.length); // 3
 *
 * // Under reduced QoS, only required tools remain
 * const reduced = registry.forBudgetLevel(QoSLevel.REDUCED);
 * console.log(reduced.length); // only required-priority tools
 * ```
 */
export class ToolRegistry {
  private readonly _tools: readonly ToolDefinition[];
  private readonly _maxTools: number;

  /**
   * Create a registry with the given tools.
   *
   * @throws {ConfigurationException} if:
   * - tools contains more than maxTools entries (default 5)
   * - tools contains duplicate tool names
   */
  constructor(tools: ToolDefinition[], maxTools: number = 5) {
    if (tools.length > maxTools) {
      throw new ConfigurationException(
        `Too many tools: ${tools.length} exceeds maximum of ${maxTools}`,
        `Small models perform best with ${maxTools} or fewer tools. ` +
          'Remove optional tools or increase maxTools if needed.'
      );
    }

    const names = new Set<string>();
    for (const tool of tools) {
      if (names.has(tool.name)) {
        throw new ConfigurationException(
          `Duplicate tool name: "${tool.name}"`,
          'Each tool in the registry must have a unique name'
        );
      }
      names.add(tool.name);
    }

    this._tools = Object.freeze([...tools]);
    this._maxTools = maxTools;
  }

  /** Unmodifiable list of all registered tools */
  get tools(): readonly ToolDefinition[] {
    return this._tools;
  }

  /** Tools with ToolPriority.REQUIRED priority */
  get requiredTools(): readonly ToolDefinition[] {
    return this._tools.filter((t) => t.priority === ToolPriority.REQUIRED);
  }

  /** Tools with ToolPriority.OPTIONAL priority */
  get optionalTools(): readonly ToolDefinition[] {
    return this._tools.filter((t) => t.priority === ToolPriority.OPTIONAL);
  }

  /** Maximum number of tools allowed in this registry */
  get maxTools(): number {
    return this._maxTools;
  }

  /**
   * Look up a tool by its function name.
   *
   * @returns null if no tool with the given name is registered
   */
  findByName(name: string): ToolDefinition | null {
    return this._tools.find((t) => t.name === name) ?? null;
  }

  /**
   * Return tools appropriate for the given QoSLevel.
   *
   * - QoSLevel.FULL -- all tools
   * - QoSLevel.REDUCED -- required tools only (optional dropped)
   * - QoSLevel.MINIMAL -- empty list (no tools under minimal QoS)
   * - QoSLevel.PAUSED -- empty list
   */
  forBudgetLevel(level: QoSLevel): readonly ToolDefinition[] {
    switch (level) {
      case QoSLevel.FULL:
        return this._tools;
      case QoSLevel.REDUCED:
        return this.requiredTools;
      case QoSLevel.MINIMAL:
      case QoSLevel.PAUSED:
        return [];
      default:
        return this._tools;
    }
  }

  toString(): string {
    return `ToolRegistry(${this._tools.length} tools, max=${this._maxTools})`;
  }
}
