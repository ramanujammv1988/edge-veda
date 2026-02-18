import 'package:flutter/foundation.dart';

import 'device_state.dart';

/// A room in the virtual smart home containing devices.
class Room {
  final RoomId id;
  final String name;
  final List<DeviceState> devices;

  Room({
    required this.id,
    required this.name,
    required this.devices,
  });
}

/// A log entry recording an action taken by the LLM intent engine.
class ActionLogEntry {
  final DateTime timestamp;
  final String description;
  final String toolName;
  final Map<String, dynamic> arguments;
  final bool success;

  const ActionLogEntry({
    required this.timestamp,
    required this.description,
    required this.toolName,
    required this.arguments,
    required this.success,
  });
}

/// Abstract interface for routing device control actions.
///
/// The [LocalActionRouter] applies actions directly to [HomeState].
/// The [HomeAssistantConnector] (in home_assistant.dart) maps actions
/// to Home Assistant REST API calls.
abstract class ActionRouter {
  Future<bool> executeAction(String toolName, Map<String, dynamic> args);
}

/// Reactive state model for the virtual smart home.
///
/// Pre-populated with 3 rooms and 10 devices. Notifies listeners
/// whenever device state changes via [applyAction].
class HomeState extends ChangeNotifier {
  late final List<Room> rooms;
  final List<ActionLogEntry> actionLog = [];

  HomeState() {
    rooms = _createDefaultRooms();
  }

  /// Look up a device by its unique ID across all rooms.
  DeviceState? getDevice(String deviceId) {
    for (final room in rooms) {
      for (final device in room.devices) {
        if (device.id == deviceId) return device;
      }
    }
    return null;
  }

  /// Get a flat list of all devices across all rooms.
  List<DeviceState> getAllDevices() {
    return rooms.expand((room) => room.devices).toList();
  }

  /// Get a text summary of all device states for LLM context.
  String getHomeStatusSummary() {
    final buffer = StringBuffer();
    for (final room in rooms) {
      buffer.writeln('${room.name}:');
      for (final device in room.devices) {
        buffer.writeln('  - ${device.toStatusString()} (id: ${device.id})');
      }
    }
    return buffer.toString();
  }

  /// Apply a tool call action to device state.
  ///
  /// Looks up the device by [args]\['device_id'\], applies the state change
  /// based on [toolName], logs the action, and notifies listeners.
  void applyAction(String toolName, Map<String, dynamic> args) {
    final deviceId = args['device_id'] as String?;
    if (deviceId == null) {
      actionLog.add(ActionLogEntry(
        timestamp: DateTime.now(),
        description: 'Failed: no device_id provided',
        toolName: toolName,
        arguments: args,
        success: false,
      ));
      notifyListeners();
      return;
    }

    final device = getDevice(deviceId);
    if (device == null) {
      actionLog.add(ActionLogEntry(
        timestamp: DateTime.now(),
        description: 'Failed: device "$deviceId" not found',
        toolName: toolName,
        arguments: args,
        success: false,
      ));
      notifyListeners();
      return;
    }

    DeviceState? updatedDevice;
    String description;

    switch (toolName) {
      case 'set_light':
        if (device is LightState) {
          updatedDevice = device.copyWith(
            isOn: args['is_on'] as bool? ?? device.isOn,
            brightness: args['brightness'] != null
                ? (args['brightness'] as num).toDouble() / 100.0
                : null,
            colorTemp: args['color_temp'] as int?,
          );
          description = 'Set ${device.name}: ${updatedDevice.toStatusString()}';
        } else {
          description = 'Failed: ${device.name} is not a light';
        }
      case 'set_thermostat':
        if (device is ThermostatState) {
          final newMode = args['mode'] as String?;
          updatedDevice = device.copyWith(
            isOn: newMode == 'off' ? false : true,
            targetTemp: args['target_temp'] != null
                ? (args['target_temp'] as num).toDouble()
                : null,
            mode: newMode,
          );
          description =
              'Set ${device.name}: ${updatedDevice.toStatusString()}';
        } else {
          description = 'Failed: ${device.name} is not a thermostat';
        }
      case 'set_lock':
        if (device is LockState) {
          updatedDevice = device.copyWith(
            isLocked: args['is_locked'] as bool?,
          );
          description = 'Set ${device.name}: ${updatedDevice.toStatusString()}';
        } else {
          description = 'Failed: ${device.name} is not a lock';
        }
      case 'set_tv':
        if (device is TvState) {
          final isOn = args['is_on'] as bool?;
          updatedDevice = device.copyWith(
            isOn: isOn,
            input: args['input'] as String?,
            volume: args['volume'] as int?,
          );
          description = 'Set ${device.name}: ${updatedDevice.toStatusString()}';
        } else {
          description = 'Failed: ${device.name} is not a TV';
        }
      case 'set_fan':
        if (device is FanState) {
          final speed = args['speed'] as int?;
          updatedDevice = device.copyWith(
            isOn: speed != null ? speed > 0 : null,
            speed: speed,
          );
          description = 'Set ${device.name}: ${updatedDevice.toStatusString()}';
        } else {
          description = 'Failed: ${device.name} is not a fan';
        }
      default:
        description = 'Unknown tool: $toolName';
    }

    if (updatedDevice != null) {
      _replaceDevice(deviceId, updatedDevice);
    }

    actionLog.add(ActionLogEntry(
      timestamp: DateTime.now(),
      description: description,
      toolName: toolName,
      arguments: args,
      success: updatedDevice != null,
    ));

    notifyListeners();
  }

  /// Replace a device in-place within its room.
  void _replaceDevice(String deviceId, DeviceState newDevice) {
    for (final room in rooms) {
      for (int i = 0; i < room.devices.length; i++) {
        if (room.devices[i].id == deviceId) {
          room.devices[i] = newDevice;
          return;
        }
      }
    }
  }

  /// Create the default 3-room home with 10 devices.
  static List<Room> _createDefaultRooms() {
    return [
      Room(
        id: RoomId.livingRoom,
        name: 'Living Room',
        devices: [
          const LightState(
            id: 'living_room_light_ceiling',
            name: 'Ceiling Light',
            room: RoomId.livingRoom,
            isOn: true,
            brightness: 0.8,
            colorTemp: 4000,
          ),
          const LightState(
            id: 'living_room_light_floor',
            name: 'Floor Lamp',
            room: RoomId.livingRoom,
            isOn: false,
            brightness: 0.5,
            colorTemp: 2700,
          ),
          const ThermostatState(
            id: 'living_room_thermostat',
            name: 'Thermostat',
            room: RoomId.livingRoom,
            isOn: true,
            targetTemp: 72.0,
            currentTemp: 71.0,
            mode: 'auto',
          ),
          const TvState(
            id: 'living_room_tv',
            name: 'TV',
            room: RoomId.livingRoom,
            isOn: false,
            input: 'off',
            volume: 30,
          ),
          const FanState(
            id: 'living_room_fan',
            name: 'Fan',
            room: RoomId.livingRoom,
            isOn: false,
            speed: 0,
          ),
        ],
      ),
      Room(
        id: RoomId.bedroom,
        name: 'Bedroom',
        devices: [
          const LightState(
            id: 'bedroom_light_main',
            name: 'Main Light',
            room: RoomId.bedroom,
            isOn: false,
            brightness: 1.0,
            colorTemp: 3000,
          ),
          const LightState(
            id: 'bedroom_light_bedside',
            name: 'Bedside Lamp',
            room: RoomId.bedroom,
            isOn: false,
            brightness: 0.3,
            colorTemp: 2700,
          ),
          const FanState(
            id: 'bedroom_fan',
            name: 'Fan',
            room: RoomId.bedroom,
            isOn: true,
            speed: 1,
          ),
        ],
      ),
      Room(
        id: RoomId.kitchen,
        name: 'Kitchen',
        devices: [
          const LightState(
            id: 'kitchen_light_main',
            name: 'Main Light',
            room: RoomId.kitchen,
            isOn: true,
            brightness: 1.0,
            colorTemp: 5000,
          ),
          const LightState(
            id: 'kitchen_light_cabinet',
            name: 'Under-Cabinet Light',
            room: RoomId.kitchen,
            isOn: true,
            brightness: 0.5,
            colorTemp: 4000,
          ),
        ],
      ),
    ];
  }
}

/// Default action router that applies actions directly to [HomeState].
class LocalActionRouter implements ActionRouter {
  final HomeState _homeState;

  LocalActionRouter(this._homeState);

  @override
  Future<bool> executeAction(String toolName, Map<String, dynamic> args) async {
    _homeState.applyAction(toolName, args);
    // Check if the last action was successful
    if (_homeState.actionLog.isNotEmpty) {
      return _homeState.actionLog.last.success;
    }
    return false;
  }
}
