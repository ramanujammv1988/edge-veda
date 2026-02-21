/// JSON recovery utilities for malformed LLM output.
///
/// LLMs sometimes produce truncated, prefixed, or otherwise malformed JSON.
/// [JsonRecovery] attempts common repairs so that the structured output
/// pipeline can salvage valid data instead of immediately failing.
library;

/// Result of a JSON recovery attempt.
class JsonRecoveryResult {
  /// The repaired JSON string, or null if unrecoverable.
  final String? repaired;

  /// Whether the input was modified during recovery.
  final bool wasModified;

  /// Human-readable descriptions of each repair applied.
  final List<String> repairs;

  const JsonRecoveryResult({
    required this.repaired,
    required this.wasModified,
    required this.repairs,
  });
}

/// Utilities for repairing common LLM JSON failures.
///
/// All methods are static (no state, utility class pattern matching
/// [SchemaValidator]).
///
/// Common failures handled:
/// - Leading/trailing text around JSON (LLMs prefix "Here is the JSON: {...}")
/// - Unclosed brackets and braces from truncated output
/// - Unterminated string literals
class JsonRecovery {
  // Prevent instantiation -- all methods are static.
  JsonRecovery._();

  /// Attempt to repair [malformed] JSON.
  ///
  /// Returns the repaired string, or null if the input is completely
  /// unrecoverable (no `{` or `[` found).
  static String? tryRepair(String malformed) {
    final result = tryRepairWithDetails(malformed);
    return result.repaired;
  }

  /// Attempt to repair [malformed] JSON with detailed results.
  ///
  /// Returns a [JsonRecoveryResult] describing what was repaired and whether
  /// the output was modified.
  static JsonRecoveryResult tryRepairWithDetails(String malformed) {
    final repairs = <String>[];
    var text = malformed;

    // Step 1: Strip leading/trailing whitespace
    final trimmed = text.trim();
    if (trimmed.length != text.length) {
      text = trimmed;
      // Don't report whitespace stripping as a repair (too noisy)
    }

    // Step 2: Find the first { or [ to determine the JSON root
    final firstBrace = text.indexOf('{');
    final firstBracket = text.indexOf('[');

    int startIndex;
    if (firstBrace < 0 && firstBracket < 0) {
      // No JSON structure found at all
      return const JsonRecoveryResult(
        repaired: null,
        wasModified: false,
        repairs: ['Unrecoverable: no { or [ found in input'],
      );
    } else if (firstBrace < 0) {
      startIndex = firstBracket;
    } else if (firstBracket < 0) {
      startIndex = firstBrace;
    } else {
      startIndex = firstBrace < firstBracket ? firstBrace : firstBracket;
    }

    // Strip leading text before the JSON
    if (startIndex > 0) {
      repairs.add(
          'Stripped $startIndex leading characters before JSON');
      text = text.substring(startIndex);
    }

    // Step 3: Find the last matching closer
    final opener = text[0]; // either { or [
    final closer = opener == '{' ? '}' : ']';
    final lastCloser = text.lastIndexOf(closer);
    if (lastCloser > 0 && lastCloser < text.length - 1) {
      final trailingCount = text.length - lastCloser - 1;
      repairs.add(
          'Stripped $trailingCount trailing characters after JSON');
      text = text.substring(0, lastCloser + 1);
    }

    // Step 4: Handle unterminated strings
    // Count unescaped quotes -- if odd, we have an unterminated string
    text = _closeUnterminatedStrings(text, repairs);

    // Step 5: Auto-close unclosed brackets and braces
    text = _closeUnclosedBrackets(text, repairs);

    final wasModified = repairs.isNotEmpty;
    return JsonRecoveryResult(
      repaired: text,
      wasModified: wasModified,
      repairs: repairs,
    );
  }

  /// Close unterminated string literals by appending a closing quote.
  static String _closeUnterminatedStrings(
      String text, List<String> repairs) {
    var inString = false;
    var escaped = false;

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == r'\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
      }
    }

    if (inString) {
      repairs.add('Closed unterminated string literal');
      return '$text"';
    }
    return text;
  }

  /// Count open brackets/braces and append missing closers.
  static String _closeUnclosedBrackets(
      String text, List<String> repairs) {
    var braceCount = 0; // { vs }
    var bracketCount = 0; // [ vs ]
    var inString = false;
    var escaped = false;

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == r'\') {
        if (inString) escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (c == '{') {
        braceCount++;
      } else if (c == '}') {
        braceCount--;
      } else if (c == '[') {
        bracketCount++;
      } else if (c == ']') {
        bracketCount--;
      }
    }

    final closers = StringBuffer();
    // Close brackets first (inner), then braces (outer) for typical nesting
    if (bracketCount > 0) {
      closers.write(']' * bracketCount);
      repairs.add('Appended $bracketCount missing ] closer(s)');
    }
    if (braceCount > 0) {
      closers.write('}' * braceCount);
      repairs.add('Appended $braceCount missing } closer(s)');
    }

    if (closers.isNotEmpty) {
      return '$text$closers';
    }
    return text;
  }
}
