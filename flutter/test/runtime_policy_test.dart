import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/runtime_policy.dart';

void main() {
  group('QoS knob mappings', () {
    test('full level returns maxFps=2, resolution=640, maxTokens=100', () {
      final knobs = RuntimePolicy.knobsForLevel(QoSLevel.full);
      expect(knobs.maxFps, 2);
      expect(knobs.resolution, 640);
      expect(knobs.maxTokens, 100);
    });

    test('reduced level returns maxFps=1, resolution=480, maxTokens=75', () {
      final knobs = RuntimePolicy.knobsForLevel(QoSLevel.reduced);
      expect(knobs.maxFps, 1);
      expect(knobs.resolution, 480);
      expect(knobs.maxTokens, 75);
    });

    test('minimal level returns maxFps=1, resolution=320, maxTokens=50', () {
      final knobs = RuntimePolicy.knobsForLevel(QoSLevel.minimal);
      expect(knobs.maxFps, 1);
      expect(knobs.resolution, 320);
      expect(knobs.maxTokens, 50);
    });

    test('paused level returns maxFps=0, resolution=0, maxTokens=0', () {
      final knobs = RuntimePolicy.knobsForLevel(QoSLevel.paused);
      expect(knobs.maxFps, 0);
      expect(knobs.resolution, 0);
      expect(knobs.maxTokens, 0);
    });
  });

  group('Thermal escalation', () {
    test('thermal=3 escalates to paused (critical)', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 3,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.paused);
    });

    test('thermal=2 escalates to minimal (serious)', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 2,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.minimal);
    });

    test('thermal=1 escalates to reduced (moderate)', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 1,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.reduced);
    });

    test('thermal=0 stays at full (nominal)', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.full);
    });
  });

  group('Memory pressure escalation', () {
    test('availableMemory < 50MB escalates to paused', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 40 * 1024 * 1024,
      );
      expect(level, QoSLevel.paused);
    });

    test('availableMemory < 100MB escalates to minimal', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 80 * 1024 * 1024,
      );
      expect(level, QoSLevel.minimal);
    });

    test('availableMemory < 200MB (threshold) escalates to reduced', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 150 * 1024 * 1024,
      );
      expect(level, QoSLevel.reduced);
    });

    test('availableMemory > 200MB stays at full', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 300 * 1024 * 1024,
      );
      expect(level, QoSLevel.full);
    });
  });

  group('Battery escalation', () {
    test('battery < 5% (0.04) escalates to minimal', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 0.04,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.minimal);
    });

    test('battery < 15% (0.10) escalates to reduced', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 0.10,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.reduced);
    });

    test('battery > 15% causes no escalation', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 0.50,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.full);
    });
  });

  group('Low power mode', () {
    test('isLowPowerMode=true with no other pressure escalates to reduced',
        () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
        isLowPowerMode: true,
      );
      expect(level, QoSLevel.reduced);
    });
  });

  group('Escalation is immediate', () {
    test('from full, thermal=2 immediately goes to minimal', () {
      final policy = RuntimePolicy();
      expect(policy.currentLevel, QoSLevel.full);

      final level = policy.evaluate(
        thermalState: 2,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.minimal);
      expect(policy.currentLevel, QoSLevel.minimal);
    });

    test('from reduced, thermal=3 immediately goes to paused', () {
      final policy = RuntimePolicy();
      // First get to reduced
      policy.evaluate(
        thermalState: 1,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.reduced);

      // Now escalate to paused
      final level = policy.evaluate(
        thermalState: 3,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.paused);
      expect(policy.currentLevel, QoSLevel.paused);
    });
  });

  group('Restoration with hysteresis', () {
    test('paused to full requires 3 restore cycles', () async {
      final policy = RuntimePolicy(
        escalationCooldown: const Duration(milliseconds: 10),
        restoreCooldown: const Duration(milliseconds: 10),
      );

      // Escalate to paused
      policy.evaluate(
        thermalState: 3,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.paused);

      // Evaluate with no pressure immediately -- stays paused (needs cooldown)
      policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.paused);

      // Wait for cooldown, then restore one level
      await Future<void>.delayed(const Duration(milliseconds: 15));
      policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.minimal);

      // Wait again, restore another level
      await Future<void>.delayed(const Duration(milliseconds: 15));
      policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.reduced);

      // Wait again, restore to full
      await Future<void>.delayed(const Duration(milliseconds: 15));
      policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.full);
    });
  });

  group('Reset', () {
    test('reset returns to full with null lastEscalation', () {
      final policy = RuntimePolicy();

      // Escalate
      policy.evaluate(
        thermalState: 3,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(policy.currentLevel, QoSLevel.paused);
      expect(policy.lastEscalation, isNotNull);

      // Reset
      policy.reset();
      expect(policy.currentLevel, QoSLevel.full);
      expect(policy.lastEscalation, isNull);
    });
  });

  group('Unavailable values', () {
    test('thermalState=-1 treated as nominal (no pressure)', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: -1,
        batteryLevel: 1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.full);
    });

    test('batteryLevel=-1.0 skips battery check', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: -1.0,
        availableMemoryBytes: 500 * 1024 * 1024,
      );
      expect(level, QoSLevel.full);
    });

    test('availableMemoryBytes=0 skips memory check', () {
      final policy = RuntimePolicy();
      final level = policy.evaluate(
        thermalState: 0,
        batteryLevel: 1.0,
        availableMemoryBytes: 0,
      );
      expect(level, QoSLevel.full);
    });
  });
}
