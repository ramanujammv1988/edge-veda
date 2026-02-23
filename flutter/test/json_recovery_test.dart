import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/json_recovery.dart';

void main() {
  group('Already valid JSON', () {
    test('object passes through unmodified', () {
      final result = JsonRecovery.tryRepairWithDetails('{"name":"John"}');
      expect(result.repaired, '{"name":"John"}');
      expect(result.wasModified, false);
    });

    test('array passes through unmodified', () {
      final result = JsonRecovery.tryRepairWithDetails('[1,2,3]');
      expect(result.repaired, '[1,2,3]');
      expect(result.wasModified, false);
    });

    test('empty object passes through', () {
      final result = JsonRecovery.tryRepairWithDetails('{}');
      expect(result.repaired, '{}');
      expect(result.wasModified, false);
    });
  });

  group('Leading/trailing garbage', () {
    test('strips leading text before JSON', () {
      final result = JsonRecovery.tryRepairWithDetails(
          'Here is the JSON: {"name":"John"}');
      expect(result.repaired, '{"name":"John"}');
      expect(result.wasModified, true);
      expect(result.repairs, contains(contains('leading characters')));
    });

    test('strips trailing text after JSON', () {
      final result = JsonRecovery.tryRepairWithDetails(
          '{"name":"John"} and that\'s it!');
      expect(result.repaired, '{"name":"John"}');
      expect(result.wasModified, true);
      expect(result.repairs, contains(contains('trailing characters')));
    });

    test('strips both leading and trailing text', () {
      final result =
          JsonRecovery.tryRepairWithDetails('Sure! {"a":1} hope that helps');
      expect(result.repaired, '{"a":1}');
      expect(result.wasModified, true);
    });
  });

  group('Truncated JSON (unclosed brackets)', () {
    test('appends } to truncated object', () {
      final result = JsonRecovery.tryRepair('{"name":"John"');
      expect(result, isNotNull);
      // Verify it is parseable
      final parsed = jsonDecode(result!);
      expect(parsed['name'], 'John');
    });

    test('appends ]} to truncated array in object', () {
      final result = JsonRecovery.tryRepair('{"items":[1,2,3');
      expect(result, isNotNull);
      final parsed = jsonDecode(result!);
      expect(parsed['items'], [1, 2, 3]);
    });

    test('appends }} to nested truncated objects', () {
      final result = JsonRecovery.tryRepair('{"a":{"b":1');
      expect(result, isNotNull);
      final parsed = jsonDecode(result!);
      expect(parsed['a']['b'], 1);
    });

    test('appends ] to truncated array', () {
      final result = JsonRecovery.tryRepair('[1,2,3');
      expect(result, isNotNull);
      final parsed = jsonDecode(result!);
      expect(parsed, [1, 2, 3]);
    });
  });

  group('Unterminated strings', () {
    test('closes unterminated string and brackets', () {
      final result = JsonRecovery.tryRepair('{"name":"John');
      expect(result, isNotNull);
      // Should be parseable after repair
      final parsed = jsonDecode(result!);
      expect(parsed['name'], 'John');
    });

    test('repaired output with unterminated string is parseable', () {
      final result =
          JsonRecovery.tryRepairWithDetails('{"title":"Hello World');
      expect(result.repaired, isNotNull);
      expect(result.wasModified, true);
      final parsed = jsonDecode(result.repaired!);
      expect(parsed['title'], 'Hello World');
    });
  });

  group('Unrecoverable', () {
    test('string without braces returns null', () {
      expect(JsonRecovery.tryRepair('"just a string"'), null);
    });

    test('plain text returns null', () {
      expect(JsonRecovery.tryRepair('hello world'), null);
    });

    test('empty string returns null', () {
      expect(JsonRecovery.tryRepair(''), null);
    });

    test('only whitespace returns null', () {
      expect(JsonRecovery.tryRepair('   \n  \t  '), null);
    });
  });

  group('tryRepairWithDetails', () {
    test('repairs list is populated for each repair type', () {
      final result = JsonRecovery.tryRepairWithDetails(
          'prefix {"name":"John');
      expect(result.repairs, isNotEmpty);
      expect(result.wasModified, true);
      // Should have: stripped leading chars, closed string, closed bracket
      expect(result.repairs.length, greaterThanOrEqualTo(2));
    });

    test('wasModified is false for clean input', () {
      final result = JsonRecovery.tryRepairWithDetails('{"a":1}');
      expect(result.wasModified, false);
      expect(result.repairs, isEmpty);
    });

    test('wasModified is true when repairs applied', () {
      final result = JsonRecovery.tryRepairWithDetails('{"a":1');
      expect(result.wasModified, true);
      expect(result.repairs, isNotEmpty);
    });
  });
}
