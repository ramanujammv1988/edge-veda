import 'package:flutter/material.dart' hide LockState;

import '../models/device_state.dart';
import '../theme.dart';

/// Animated device card that renders the correct visualization for each
/// device type. Wraps content in [AnimatedSwitcher] so state changes
/// animate smoothly.
class DeviceCard extends StatelessWidget {
  final DeviceState device;

  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    return Container(
      key: ValueKey('${device.id}_$_stateHash'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: icon + name + on/off dot
          Row(
            children: [
              _buildDeviceIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _onOffDot(),
            ],
          ),
          const SizedBox(height: 10),
          // Bottom: device-specific state
          _buildDeviceState(),
        ],
      ),
    );
  }

  /// A small colored dot indicating on (green) or off (grey).
  Widget _onOffDot() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: device.isOn ? AppTheme.success : AppTheme.textTertiary,
        shape: BoxShape.circle,
      ),
    );
  }

  /// Build the leading icon based on device type and state.
  Widget _buildDeviceIcon() {
    final IconData icon;
    final Color color;

    switch (device.type) {
      case DeviceType.light:
        final light = device as LightState;
        icon = device.isOn ? Icons.lightbulb : Icons.lightbulb_outline;
        color = device.isOn
            ? Color.lerp(
                const Color(0xFF8D6E00),
                const Color(0xFFFFD54F),
                light.brightness,
              )!
            : AppTheme.textTertiary;
      case DeviceType.thermostat:
        final thermo = device as ThermostatState;
        icon = Icons.thermostat;
        if (!device.isOn || thermo.mode == 'off') {
          color = AppTheme.textTertiary;
        } else if (thermo.mode == 'heat') {
          color = AppTheme.accent;
        } else if (thermo.mode == 'cool') {
          color = const Color(0xFF42A5F5);
        } else {
          color = AppTheme.accent; // auto
        }
      case DeviceType.lock:
        final lock = device as LockState;
        icon = lock.isLocked ? Icons.lock : Icons.lock_open;
        color = lock.isLocked ? AppTheme.success : AppTheme.error;
      case DeviceType.tv:
        icon = Icons.tv;
        color = device.isOn ? AppTheme.accent : AppTheme.textTertiary;
      case DeviceType.fan:
        icon = Icons.air;
        color = device.isOn ? AppTheme.accent : AppTheme.textTertiary;
    }

    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) => Icon(icon, color: value, size: 22),
    );
  }

  /// Build the device-specific state visualization.
  Widget _buildDeviceState() {
    switch (device.type) {
      case DeviceType.light:
        return _buildLightState(device as LightState);
      case DeviceType.thermostat:
        return _buildThermostatState(device as ThermostatState);
      case DeviceType.lock:
        return _buildLockState(device as LockState);
      case DeviceType.tv:
        return _buildTvState(device as TvState);
      case DeviceType.fan:
        return _buildFanState(device as FanState);
    }
  }

  // -- Light ------------------------------------------------------------------

  Widget _buildLightState(LightState light) {
    final pct = (light.brightness * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          light.isOn ? '$pct%' : 'Off',
          style: TextStyle(
            fontSize: 12,
            color: light.isOn ? AppTheme.textSecondary : AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      width: constraints.maxWidth,
                      color: AppTheme.surfaceVariant,
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: light.isOn
                          ? constraints.maxWidth * light.brightness
                          : 0,
                      color: const Color(0xFFFFB300), // amber
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // -- Thermostat -------------------------------------------------------------

  Widget _buildThermostatState(ThermostatState thermo) {
    final modeLabel = thermo.mode.toUpperCase();
    final Color modeColor;
    switch (thermo.mode) {
      case 'heat':
        modeColor = AppTheme.accent;
      case 'cool':
        modeColor = const Color(0xFF42A5F5);
      default:
        modeColor = AppTheme.textSecondary;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${thermo.targetTemp.round()}\u00B0F',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: modeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            modeLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: modeColor,
            ),
          ),
        ),
      ],
    );
  }

  // -- Lock -------------------------------------------------------------------

  Widget _buildLockState(LockState lock) {
    return Text(
      lock.isLocked ? 'Locked' : 'Unlocked',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: lock.isLocked ? AppTheme.success : AppTheme.error,
      ),
    );
  }

  // -- TV ---------------------------------------------------------------------

  Widget _buildTvState(TvState tv) {
    if (!tv.isOn) {
      return const Text(
        'Off',
        style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatInput(tv.input),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.volume_up, size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: tv.volume / 100.0,
                    backgroundColor: AppTheme.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${tv.volume}',
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatInput(String input) {
    switch (input) {
      case 'hdmi1':
        return 'HDMI 1';
      case 'hdmi2':
        return 'HDMI 2';
      case 'streaming':
        return 'Streaming';
      default:
        return input;
    }
  }

  // -- Fan --------------------------------------------------------------------

  Widget _buildFanState(FanState fan) {
    final String label;
    if (!fan.isOn || fan.speed == 0) {
      label = 'Off';
    } else {
      label = 'Speed ${fan.speed}';
    }
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: fan.isOn ? AppTheme.textSecondary : AppTheme.textTertiary,
          ),
        ),
        if (fan.isOn && fan.speed > 0) ...[
          const SizedBox(width: 6),
          ...List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 4,
                height: 6 + (i + 1) * 3.0,
                decoration: BoxDecoration(
                  color: i < fan.speed
                      ? AppTheme.accent
                      : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  // -- Hash -------------------------------------------------------------------

  /// State hash for AnimatedSwitcher change detection.
  String get _stateHash {
    switch (device.type) {
      case DeviceType.light:
        final l = device as LightState;
        return '${l.isOn}_${l.brightness}_${l.colorTemp}';
      case DeviceType.thermostat:
        final t = device as ThermostatState;
        return '${t.isOn}_${t.targetTemp}_${t.mode}';
      case DeviceType.lock:
        final k = device as LockState;
        return '${k.isLocked}';
      case DeviceType.tv:
        final v = device as TvState;
        return '${v.isOn}_${v.input}_${v.volume}';
      case DeviceType.fan:
        final f = device as FanState;
        return '${f.isOn}_${f.speed}';
    }
  }
}
