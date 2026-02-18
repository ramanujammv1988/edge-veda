/// Device type enums and state classes for all 5 smart home device types.
///
/// Each device state is immutable with [copyWith] for state updates
/// and [toStatusString] for human-readable status.
library;

/// The 5 supported device types in the virtual smart home.
enum DeviceType { light, thermostat, lock, tv, fan }

/// Room identifiers for the 3-room demo home.
enum RoomId { livingRoom, bedroom, kitchen }

/// Base class for all device states.
///
/// Each device has a unique [id], display [name], [type], [room], and
/// power [isOn] state. Concrete subclasses add device-specific properties.
abstract class DeviceState {
  final String id;
  final String name;
  final DeviceType type;
  final RoomId room;
  final bool isOn;

  const DeviceState({
    required this.id,
    required this.name,
    required this.type,
    required this.room,
    required this.isOn,
  });

  /// Human-readable room name from [RoomId].
  String get roomName {
    switch (room) {
      case RoomId.livingRoom:
        return 'Living Room';
      case RoomId.bedroom:
        return 'Bedroom';
      case RoomId.kitchen:
        return 'Kitchen';
    }
  }

  /// Human-readable status string (e.g., "Living Room Light: ON, 80% brightness").
  String toStatusString();
}

/// Light device state with brightness and color temperature.
class LightState extends DeviceState {
  /// Brightness level from 0.0 (off) to 1.0 (full).
  final double brightness;

  /// Color temperature in Kelvin (2700 warm - 6500 cool daylight).
  final int colorTemp;

  const LightState({
    required super.id,
    required super.name,
    required super.room,
    required super.isOn,
    this.brightness = 1.0,
    this.colorTemp = 4000,
  }) : super(type: DeviceType.light);

  LightState copyWith({
    bool? isOn,
    double? brightness,
    int? colorTemp,
  }) {
    return LightState(
      id: id,
      name: name,
      room: room,
      isOn: isOn ?? this.isOn,
      brightness: brightness ?? this.brightness,
      colorTemp: colorTemp ?? this.colorTemp,
    );
  }

  @override
  String toStatusString() {
    final state = isOn ? 'ON' : 'OFF';
    final pct = (brightness * 100).round();
    return '$roomName $name: $state, $pct% brightness, ${colorTemp}K';
  }
}

/// Thermostat device state with target/current temperature and mode.
class ThermostatState extends DeviceState {
  /// Target temperature in Fahrenheit (60-85).
  final double targetTemp;

  /// Current measured temperature in Fahrenheit.
  final double currentTemp;

  /// Operating mode: heat, cool, auto, or off.
  final String mode;

  const ThermostatState({
    required super.id,
    required super.name,
    required super.room,
    required super.isOn,
    this.targetTemp = 72.0,
    this.currentTemp = 71.0,
    this.mode = 'auto',
  }) : super(type: DeviceType.thermostat);

  ThermostatState copyWith({
    bool? isOn,
    double? targetTemp,
    double? currentTemp,
    String? mode,
  }) {
    return ThermostatState(
      id: id,
      name: name,
      room: room,
      isOn: isOn ?? this.isOn,
      targetTemp: targetTemp ?? this.targetTemp,
      currentTemp: currentTemp ?? this.currentTemp,
      mode: mode ?? this.mode,
    );
  }

  @override
  String toStatusString() {
    final state = isOn ? 'ON' : 'OFF';
    return '$roomName $name: $state, target ${targetTemp.round()}F, current ${currentTemp.round()}F, mode: $mode';
  }
}

/// Lock device state with locked/unlocked status.
class LockState extends DeviceState {
  /// Whether the lock is engaged.
  final bool isLocked;

  const LockState({
    required super.id,
    required super.name,
    required super.room,
    required super.isOn,
    this.isLocked = true,
  }) : super(type: DeviceType.lock);

  LockState copyWith({
    bool? isOn,
    bool? isLocked,
  }) {
    return LockState(
      id: id,
      name: name,
      room: room,
      isOn: isOn ?? this.isOn,
      isLocked: isLocked ?? this.isLocked,
    );
  }

  @override
  String toStatusString() {
    final lockState = isLocked ? 'LOCKED' : 'UNLOCKED';
    return '$roomName $name: $lockState';
  }
}

/// TV device state with input source and volume.
class TvState extends DeviceState {
  /// Input source: hdmi1, hdmi2, streaming, or off.
  final String input;

  /// Volume level from 0 to 100.
  final int volume;

  const TvState({
    required super.id,
    required super.name,
    required super.room,
    required super.isOn,
    this.input = 'off',
    this.volume = 30,
  }) : super(type: DeviceType.tv);

  TvState copyWith({
    bool? isOn,
    String? input,
    int? volume,
  }) {
    return TvState(
      id: id,
      name: name,
      room: room,
      isOn: isOn ?? this.isOn,
      input: input ?? this.input,
      volume: volume ?? this.volume,
    );
  }

  @override
  String toStatusString() {
    final state = isOn ? 'ON' : 'OFF';
    return '$roomName $name: $state, input: $input, volume: $volume';
  }
}

/// Fan device state with speed control.
class FanState extends DeviceState {
  /// Fan speed from 0 (off) to 3 (high).
  final int speed;

  const FanState({
    required super.id,
    required super.name,
    required super.room,
    required super.isOn,
    this.speed = 0,
  }) : super(type: DeviceType.fan);

  FanState copyWith({
    bool? isOn,
    int? speed,
  }) {
    return FanState(
      id: id,
      name: name,
      room: room,
      isOn: isOn ?? this.isOn,
      speed: speed ?? this.speed,
    );
  }

  @override
  String toStatusString() {
    final state = isOn ? 'ON' : 'OFF';
    final speedLabel = speed == 0 ? 'off' : 'speed $speed';
    return '$roomName $name: $state, $speedLabel';
  }
}
