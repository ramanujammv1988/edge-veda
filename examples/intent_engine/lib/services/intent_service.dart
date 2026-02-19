/// LLM intent engine using Edge Veda SDK's sendWithTools for natural language
/// smart home control.
///
/// Wraps Qwen3-0.6B model with 6 tool definitions that map to device control
/// operations. Uses [ChatSession.sendWithTools] for multi-round tool calling.
library;

import 'package:edge_veda/edge_veda.dart';

import '../models/home_state.dart';

/// Result of processing a natural language intent.
class IntentResult {
  /// The LLM's response text explaining what it did.
  final String message;

  /// Actions taken during intent processing.
  final List<ActionLogEntry> actions;

  /// Whether all actions completed successfully.
  final bool success;

  const IntentResult({
    required this.message,
    required this.actions,
    required this.success,
  });
}

/// LLM-powered intent service for smart home control.
///
/// Uses Qwen3-0.6B with [ChatSession.sendWithTools] to parse natural language
/// into structured device commands. The system prompt includes current home
/// status so the model knows what devices exist and their current states.
///
/// Example:
/// ```dart
/// final service = IntentService(homeState: homeState);
/// await service.init(onStatus: print, onProgress: (p) {});
/// final result = await service.processIntent('Turn on the living room lights');
/// print(result.message);
/// ```
class IntentService {
  final ModelManager _modelManager = ModelManager();
  EdgeVeda? _edgeVeda;
  ChatSession? _session;
  final HomeState _homeState;

  /// Whether the service is fully initialized and ready for intents.
  bool get isReady => _session != null;

  /// Whether initialization is in progress.
  bool isInitializing = false;

  IntentService({required HomeState homeState}) : _homeState = homeState;

  /// Initialize the service: download Qwen3-0.6B and create ChatSession.
  ///
  /// [onStatus] reports status messages (e.g., "Downloading model...").
  /// [onProgress] reports download progress (0.0 to 1.0).
  Future<void> init({
    required Function(String) onStatus,
    required Function(double) onProgress,
  }) async {
    isInitializing = true;

    try {
      // Download Qwen3-0.6B model for tool calling
      onStatus('Downloading Qwen3 0.6B (397 MB)...');
      const model = ModelRegistry.qwen3_06b;
      late final String modelPath;

      final isDownloaded = await _modelManager.isModelDownloaded(model.id);
      if (!isDownloaded) {
        final sub = _modelManager.downloadProgress.listen((p) {
          onProgress(p.progressPercent / 100.0 * 0.7); // 0-70%
        });
        modelPath = await _modelManager.downloadModel(model);
        await sub.cancel();
      } else {
        modelPath = await _modelManager.getModelPath(model.id);
      }
      onProgress(0.7);

      // Initialize EdgeVeda
      onStatus('Initializing LLM...');
      _edgeVeda = EdgeVeda();
      await _edgeVeda!.init(EdgeVedaConfig(
        modelPath: modelPath,
        contextLength: 4096,
        useGpu: true,
        numThreads: 4,
        maxMemoryMb: 1024,
        verbose: false,
      ));
      onProgress(0.9);

      // Create ChatSession with tools
      _createSession();
      onStatus('Ready');
      onProgress(1.0);
    } finally {
      isInitializing = false;
    }
  }

  /// Create or recreate the ChatSession with fresh home status in system prompt.
  void _createSession() {
    final systemPrompt = _buildSystemPrompt();
    final tools = _createToolRegistry();

    _session = ChatSession(
      edgeVeda: _edgeVeda!,
      templateFormat: ChatTemplateFormat.qwen3,
      systemPrompt: systemPrompt,
      maxResponseTokens: 512,
      tools: tools,
    );
  }

  /// Build the system prompt with current home status and device IDs.
  String _buildSystemPrompt() {
    return '''You are a smart home assistant. Control home devices by calling the appropriate tools. When the user describes a scene or activity, determine which devices need to change and call the tools. Always explain what you're doing briefly.

Available device IDs:
- living_room_light_ceiling: Living Room Ceiling Light
- living_room_light_floor: Living Room Floor Lamp
- living_room_thermostat: Living Room Thermostat
- living_room_tv: Living Room TV
- living_room_fan: Living Room Fan
- front_door_lock: Front Door Lock
- bedroom_light_main: Bedroom Main Light
- bedroom_light_bedside: Bedroom Bedside Lamp
- bedroom_fan: Bedroom Fan
- kitchen_light_main: Kitchen Main Light
- kitchen_light_cabinet: Kitchen Under-Cabinet Light

Current home status:
${_homeState.getHomeStatusSummary()}''';
  }

  /// Create the tool registry with 6 smart home tools.
  ToolRegistry _createToolRegistry() {
    return ToolRegistry([
      ToolDefinition(
        name: 'set_light',
        description:
            'Turn a light on/off or change its brightness. Use brightness '
            '0-100 where 100 is full bright. Use color_temp 2700-6500 for '
            'warm to cool white. Use device_id to specify which light.',
        parameters: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description': 'The light device ID (e.g., living_room_light_ceiling)',
            },
            'is_on': {
              'type': 'boolean',
              'description': 'Whether to turn the light on (true) or off (false)',
            },
            'brightness': {
              'type': 'number',
              'description': 'Brightness level from 0 to 100',
            },
            'color_temp': {
              'type': 'number',
              'description': 'Color temperature in Kelvin, 2700 (warm) to 6500 (cool daylight)',
            },
          },
          'required': ['device_id'],
        },
      ),
      ToolDefinition(
        name: 'set_thermostat',
        description:
            'Set the thermostat temperature or mode. Temperature is in '
            'Fahrenheit (60-85). Mode can be heat, cool, auto, or off.',
        parameters: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description': 'The thermostat device ID (e.g., living_room_thermostat)',
            },
            'target_temp': {
              'type': 'number',
              'description': 'Target temperature in Fahrenheit, 60 to 85',
            },
            'mode': {
              'type': 'string',
              'description': 'Operating mode: heat, cool, auto, or off',
            },
          },
          'required': ['device_id'],
        },
      ),
      ToolDefinition(
        name: 'set_lock',
        description:
            'Lock or unlock a door lock. Set is_locked to true to lock, '
            'false to unlock.',
        parameters: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description': 'The lock device ID',
            },
            'is_locked': {
              'type': 'boolean',
              'description': 'Whether to lock (true) or unlock (false)',
            },
          },
          'required': ['device_id', 'is_locked'],
        },
      ),
      ToolDefinition(
        name: 'set_tv',
        description:
            'Turn the TV on/off, change input source, or adjust volume. '
            'Input can be hdmi1, hdmi2, or streaming. Volume is 0-100.',
        parameters: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description': 'The TV device ID (e.g., living_room_tv)',
            },
            'is_on': {
              'type': 'boolean',
              'description': 'Whether to turn the TV on (true) or off (false)',
            },
            'input': {
              'type': 'string',
              'description': 'Input source: hdmi1, hdmi2, or streaming',
            },
            'volume': {
              'type': 'number',
              'description': 'Volume level from 0 to 100',
            },
          },
          'required': ['device_id'],
        },
      ),
      ToolDefinition(
        name: 'set_fan',
        description:
            'Set fan speed. Speed 0 turns the fan off. Speed 1 is low, '
            '2 is medium, 3 is high.',
        parameters: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description': 'The fan device ID (e.g., living_room_fan)',
            },
            'speed': {
              'type': 'number',
              'description': 'Fan speed: 0 (off), 1 (low), 2 (medium), 3 (high)',
            },
          },
          'required': ['device_id'],
        },
      ),
      ToolDefinition(
        name: 'get_home_status',
        description:
            'Get the current status of all devices in the home. No '
            'parameters needed. Returns a summary of every device.',
        parameters: {
          'type': 'object',
          'properties': {},
        },
      ),
    ], maxTools: 6);
  }

  /// Process a natural language intent and return the result.
  ///
  /// Uses [ChatSession.sendWithTools] for multi-round tool calling.
  /// After processing, refreshes the system prompt with updated home status.
  Future<IntentResult> processIntent(String userMessage) async {
    if (_session == null) {
      return const IntentResult(
        message: 'Service not initialized',
        actions: [],
        success: false,
      );
    }

    final actionsBefore = _homeState.actionLog.length;

    try {
      final reply = await _session!.sendWithTools(
        userMessage,
        onToolCall: _handleToolCall,
        maxToolRounds: 3,
      );

      final newActions = _homeState.actionLog.sublist(actionsBefore);

      return IntentResult(
        message: reply.content,
        actions: newActions,
        success: true,
      );
    } catch (e) {
      return IntentResult(
        message: 'Error: $e',
        actions: [],
        success: false,
      );
    }
  }

  /// Handle a tool call from the LLM.
  Future<ToolResult> _handleToolCall(ToolCall toolCall) async {
    switch (toolCall.name) {
      case 'get_home_status':
        return ToolResult.success(
          toolCallId: toolCall.id,
          data: {'status': _homeState.getHomeStatusSummary()},
        );

      case 'set_light':
      case 'set_thermostat':
      case 'set_lock':
      case 'set_tv':
      case 'set_fan':
        try {
          _homeState.applyAction(toolCall.name, toolCall.arguments);
          final lastAction = _homeState.actionLog.last;
          if (lastAction.success) {
            return ToolResult.success(
              toolCallId: toolCall.id,
              data: {'result': lastAction.description},
            );
          } else {
            return ToolResult.failure(
              toolCallId: toolCall.id,
              error: lastAction.description,
            );
          }
        } catch (e) {
          return ToolResult.failure(
            toolCallId: toolCall.id,
            error: 'Action failed: $e',
          );
        }

      default:
        return ToolResult.failure(
          toolCallId: toolCall.id,
          error: 'Unknown tool: ${toolCall.name}',
        );
    }
  }

  /// Reset conversation context (start fresh).
  void reset() {
    _session?.reset();
    // Recreate session with current home status
    if (_edgeVeda != null) {
      _createSession();
    }
  }

  /// Dispose all resources.
  void dispose() {
    _session = null;
    _edgeVeda?.dispose();
    _edgeVeda = null;
  }
}
