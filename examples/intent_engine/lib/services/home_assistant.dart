/// Home Assistant REST API connector stub.
///
/// Maps tool call actions to Home Assistant REST API endpoints. Currently
/// simulates actions by printing curl commands -- does NOT make actual HTTP
/// calls. Designed to be wired to a real Home Assistant instance.
///
/// ## How to connect to a real Home Assistant instance:
///
/// 1. **Get a Long-Lived Access Token:**
///    - Open your Home Assistant UI
///    - Go to Profile (bottom-left) > Security > Long-Lived Access Tokens
///    - Click "Create Token", give it a name, and copy the token
///
/// 2. **Find Entity IDs:**
///    - Go to Developer Tools > States in your HA UI
///    - Entity IDs look like: light.living_room, climate.thermostat, etc.
///
/// 3. **Wire the connector:**
///    ```dart
///    final ha = HomeAssistantConnector(
///      baseUrl: 'http://homeassistant.local:8123',
///      bearerToken: 'your-long-lived-access-token',
///    );
///    ```
///
/// 4. **Replace print() calls with actual http.post() calls** using the
///    endpoint, headers, and body from [HomeAssistantAction].
library;

import '../models/home_state.dart';

/// A structured Home Assistant API action (not yet executed).
class HomeAssistantAction {
  /// REST API endpoint (e.g., /api/services/light/turn_on).
  final String endpoint;

  /// HTTP method (always POST for HA service calls).
  final String method;

  /// HTTP headers including Authorization.
  final Map<String, String> headers;

  /// JSON request body.
  final Map<String, dynamic> body;

  const HomeAssistantAction({
    required this.endpoint,
    required this.method,
    required this.headers,
    required this.body,
  });

  /// Generate a curl command for debugging/documentation.
  String toCurlCommand(String baseUrl) {
    final headerStr = headers.entries
        .map((e) => "-H '${e.key}: ${e.value}'")
        .join(' ');
    final bodyStr = body.isNotEmpty
        ? "-d '${_jsonEncode(body)}'"
        : '';
    return 'curl -X $method $headerStr $bodyStr $baseUrl$endpoint';
  }

  /// Simple JSON encode without importing dart:convert at top level.
  static String _jsonEncode(Map<String, dynamic> data) {
    final entries = data.entries.map((e) {
      final value = e.value is String ? '"${e.value}"' : '${e.value}';
      return '"${e.key}": $value';
    });
    return '{${entries.join(', ')}}';
  }
}

/// Home Assistant REST API connector that maps tool calls to HA service calls.
///
/// Implements [ActionRouter] so it can be swapped in for [LocalActionRouter].
/// Currently simulates actions by logging them to the console.
class HomeAssistantConnector implements ActionRouter {
  /// Home Assistant base URL (e.g., "http://homeassistant.local:8123").
  final String? baseUrl;

  /// Long-lived access token for authentication.
  final String? bearerToken;

  /// Whether both baseUrl and bearerToken are configured.
  bool get isConfigured => baseUrl != null && bearerToken != null;

  HomeAssistantConnector({this.baseUrl, this.bearerToken});

  /// Common headers for all HA API calls.
  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${bearerToken ?? ""}',
        'Content-Type': 'application/json',
      };

  @override
  Future<bool> executeAction(String toolName, Map<String, dynamic> args) async {
    final action = _mapToolToAction(toolName, args);
    if (action == null) return false;

    // Log the action that WOULD be sent (stub -- no actual HTTP call)
    final url = baseUrl ?? 'http://homeassistant.local:8123';
    // ignore: avoid_print
    print('[HA] Would call: POST $url${action.endpoint} with ${action.body}');
    // ignore: avoid_print
    print('[HA] curl: ${action.toCurlCommand(url)}');

    return true; // Simulated success
  }

  /// Map a tool call to a Home Assistant REST API action.
  HomeAssistantAction? _mapToolToAction(
    String toolName,
    Map<String, dynamic> args,
  ) {
    switch (toolName) {
      case 'set_light':
        return _mapSetLight(args);
      case 'set_thermostat':
        return _mapSetThermostat(args);
      case 'set_lock':
        return _mapSetLock(args);
      case 'set_tv':
        return _mapSetTv(args);
      case 'set_fan':
        return _mapSetFan(args);
      default:
        return null;
    }
  }

  HomeAssistantAction _mapSetLight(Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String? ?? '';
    final isOn = args['is_on'] as bool? ?? true;
    final entityId = 'light.${deviceId.replaceAll('_light', '')}';

    final endpoint = isOn
        ? '/api/services/light/turn_on'
        : '/api/services/light/turn_off';

    final body = <String, dynamic>{
      'entity_id': entityId,
    };

    if (isOn) {
      final brightness = args['brightness'] as num?;
      if (brightness != null) {
        body['brightness_pct'] = brightness.toInt();
      }
      final colorTemp = args['color_temp'] as num?;
      if (colorTemp != null) {
        // HA uses mireds (1,000,000 / kelvin)
        body['color_temp'] = (1000000 / colorTemp.toDouble()).round();
      }
    }

    return HomeAssistantAction(
      endpoint: endpoint,
      method: 'POST',
      headers: _headers,
      body: body,
    );
  }

  HomeAssistantAction _mapSetThermostat(Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String? ?? '';
    final entityId = 'climate.$deviceId';
    final mode = args['mode'] as String?;

    if (mode == 'off') {
      return HomeAssistantAction(
        endpoint: '/api/services/climate/turn_off',
        method: 'POST',
        headers: _headers,
        body: {'entity_id': entityId},
      );
    }

    final body = <String, dynamic>{
      'entity_id': entityId,
    };

    final targetTemp = args['target_temp'] as num?;
    if (targetTemp != null) {
      body['temperature'] = targetTemp;
    }
    if (mode != null) {
      body['hvac_mode'] = mode;
    }

    return HomeAssistantAction(
      endpoint: '/api/services/climate/set_temperature',
      method: 'POST',
      headers: _headers,
      body: body,
    );
  }

  HomeAssistantAction _mapSetLock(Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String? ?? '';
    final isLocked = args['is_locked'] as bool? ?? true;
    final entityId = 'lock.$deviceId';

    return HomeAssistantAction(
      endpoint: isLocked
          ? '/api/services/lock/lock'
          : '/api/services/lock/unlock',
      method: 'POST',
      headers: _headers,
      body: {'entity_id': entityId},
    );
  }

  HomeAssistantAction _mapSetTv(Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String? ?? '';
    final isOn = args['is_on'] as bool?;
    final entityId = 'media_player.$deviceId';

    if (isOn == false) {
      return HomeAssistantAction(
        endpoint: '/api/services/media_player/turn_off',
        method: 'POST',
        headers: _headers,
        body: {'entity_id': entityId},
      );
    }

    final body = <String, dynamic>{
      'entity_id': entityId,
    };

    final input = args['input'] as String?;
    if (input != null) {
      body['source'] = input;
    }
    final volume = args['volume'] as num?;
    if (volume != null) {
      body['volume_level'] = volume.toDouble() / 100.0;
    }

    return HomeAssistantAction(
      endpoint: '/api/services/media_player/turn_on',
      method: 'POST',
      headers: _headers,
      body: body,
    );
  }

  HomeAssistantAction _mapSetFan(Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String? ?? '';
    final speed = args['speed'] as int? ?? 0;
    final entityId = 'fan.$deviceId';

    if (speed == 0) {
      return HomeAssistantAction(
        endpoint: '/api/services/fan/turn_off',
        method: 'POST',
        headers: _headers,
        body: {'entity_id': entityId},
      );
    }

    // Map speed 1-3 to percentage (33%, 66%, 100%)
    final percentage = (speed * 100 / 3).round();

    return HomeAssistantAction(
      endpoint: '/api/services/fan/set_percentage',
      method: 'POST',
      headers: _headers,
      body: {
        'entity_id': entityId,
        'percentage': percentage,
      },
    );
  }
}
