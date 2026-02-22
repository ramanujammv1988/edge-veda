import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/budget.dart';

void main() {
  group('EdgeVedaBudget.validate()', () {
    test('p95LatencyMs=300 produces warning (< 500 unrealistic)', () {
      const budget = EdgeVedaBudget(p95LatencyMs: 300);
      final warnings = budget.validate();
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('p95LatencyMs'));
    });

    test('p95LatencyMs=2000 produces no warning', () {
      const budget = EdgeVedaBudget(p95LatencyMs: 2000);
      final warnings = budget.validate();
      expect(warnings, isEmpty);
    });

    test('batteryDrainPerTenMinutes=0.3 produces warning (< 0.5 restrictive)',
        () {
      const budget = EdgeVedaBudget(batteryDrainPerTenMinutes: 0.3);
      final warnings = budget.validate();
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('batteryDrainPerTenMinutes'));
    });

    test('memoryCeilingMb=500 produces warning (< 2000 too low for VLM)', () {
      const budget = EdgeVedaBudget(memoryCeilingMb: 500);
      final warnings = budget.validate();
      expect(warnings, isNotEmpty);
      expect(warnings.first, contains('memoryCeilingMb'));
    });

    test('all null produces empty warnings', () {
      const budget = EdgeVedaBudget();
      final warnings = budget.validate();
      expect(warnings, isEmpty);
    });
  });

  group('EdgeVedaBudget.resolve() conservative', () {
    final baseline = MeasuredBaseline(
      measuredP95Ms: 1000,
      measuredDrainPerTenMin: 3.0,
      currentThermalState: 0,
      currentRssMb: 500,
      sampleCount: 20,
      measuredAt: DateTime.now(),
    );

    test('p95 = measuredP95 * 2.0', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.conservative, baseline);
      expect(resolved.p95LatencyMs, 2000);
    });

    test('drain = measuredDrain * 0.6', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.conservative, baseline);
      expect(resolved.batteryDrainPerTenMinutes, closeTo(1.8, 0.01));
    });

    test('drain = null when baseline drain is null', () {
      final nodrainBaseline = MeasuredBaseline(
        measuredP95Ms: 1000,
        measuredDrainPerTenMin: null,
        currentThermalState: 0,
        currentRssMb: 500,
        sampleCount: 20,
        measuredAt: DateTime.now(),
      );
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.conservative, nodrainBaseline);
      expect(resolved.batteryDrainPerTenMinutes, isNull);
    });

    test('thermal = max(currentThermal, 1)', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.conservative, baseline);
      expect(resolved.maxThermalLevel, 1); // max(0, 1) = 1
    });
  });

  group('EdgeVedaBudget.resolve() balanced', () {
    final baseline = MeasuredBaseline(
      measuredP95Ms: 1000,
      measuredDrainPerTenMin: 3.0,
      currentThermalState: 0,
      currentRssMb: 500,
      sampleCount: 20,
      measuredAt: DateTime.now(),
    );

    test('p95 = measuredP95 * 1.5', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.balanced, baseline);
      expect(resolved.p95LatencyMs, 1500);
    });

    test('drain = measuredDrain * 1.0', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.balanced, baseline);
      expect(resolved.batteryDrainPerTenMinutes, closeTo(3.0, 0.01));
    });

    test('thermal = 1 (always Fair)', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.balanced, baseline);
      expect(resolved.maxThermalLevel, 1);
    });
  });

  group('EdgeVedaBudget.resolve() performance', () {
    final baseline = MeasuredBaseline(
      measuredP95Ms: 1000,
      measuredDrainPerTenMin: 3.0,
      currentThermalState: 0,
      currentRssMb: 500,
      sampleCount: 20,
      measuredAt: DateTime.now(),
    );

    test('p95 = measuredP95 * 1.1', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.performance, baseline);
      expect(resolved.p95LatencyMs, 1100);
    });

    test('drain = measuredDrain * 1.5', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.performance, baseline);
      expect(resolved.batteryDrainPerTenMinutes, closeTo(4.5, 0.01));
    });

    test('thermal = 3 (allow critical)', () {
      final resolved =
          EdgeVedaBudget.resolve(BudgetProfile.performance, baseline);
      expect(resolved.maxThermalLevel, 3);
    });
  });

  group('EdgeVedaBudget.adaptive()', () {
    test('adaptiveProfile returns the profile', () {
      final budget = EdgeVedaBudget.adaptive(BudgetProfile.balanced);
      expect(budget.adaptiveProfile, BudgetProfile.balanced);
    });

    test('regular budget adaptiveProfile returns null', () {
      const budget = EdgeVedaBudget(p95LatencyMs: 2000);
      expect(budget.adaptiveProfile, isNull);
    });
  });
}
