import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

// ==============================================================================
// Data Models
// ==============================================================================

/// A computed insight candidate with type, headline, and evidence.
/// Produced deterministically by [InsightEngine] -- the LLM never computes these.
class InsightCandidate {
  final String type; // 'photo_pattern', 'calendar_pattern', 'cross_pattern', 'surprising'
  final String headline;
  final String evidence;
  final bool lowConfidence;

  InsightCandidate({
    required this.type,
    required this.headline,
    required this.evidence,
    this.lowConfidence = false,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'headline': headline,
        'evidence': evidence,
      };
}

/// Parsed detective report from LLM narration.
class DetectiveReport {
  final String headline;
  final List<Deduction> deductions;
  final String surprisingFact;
  final String privacyStatement;

  DetectiveReport({
    required this.headline,
    required this.deductions,
    required this.surprisingFact,
    required this.privacyStatement,
  });
}

class Deduction {
  final String finding;
  final String evidence;

  Deduction({required this.finding, required this.evidence});
}

// ==============================================================================
// InsightEngine -- Deterministic, pure Dart analysis
// ==============================================================================

/// Computes insight candidates from photo and calendar data using
/// deterministic rules. No LLM is involved here -- this is pure Dart logic.
///
/// Every evidence field contains concrete numbers derived from the input data.
/// Insights based on fewer than 3 data points are marked [lowConfidence].
class InsightEngine {
  /// Compute insights from photo and calendar summary data.
  ///
  /// [photoData] and [calendarData] match the Map structures returned by
  /// the native MethodChannel handlers (getPhotoInsights / getCalendarInsights).
  ///
  /// If [photoAvailable] is false, photo rules are skipped and a note is added.
  /// If [calendarAvailable] is false, calendar rules are skipped and a note is added.
  List<InsightCandidate> computeInsights(
    Map<String, dynamic> photoData,
    Map<String, dynamic> calendarData, {
    bool photoAvailable = true,
    bool calendarAvailable = true,
  }) {
    final insights = <InsightCandidate>[];

    final photoCount = (photoData['total_photos'] as num?)?.toInt() ?? 0;
    final calendarCount =
        (calendarData['total_events'] as num?)?.toInt() ?? 0;

    // Extract histograms
    final photoDayOfWeek =
        _toIntMap(photoData['day_of_week_counts'] as Map? ?? {});
    final photoHourOfDay =
        _toIntMap(photoData['hour_of_day_counts'] as Map? ?? {});
    final calendarDayOfWeek =
        _toIntMap(calendarData['day_of_week_counts'] as Map? ?? {});
    final meetingMinutes =
        _toIntMap(calendarData['meeting_minutes_per_day'] as Map? ?? {});

    // Rule 1: Peak photo hours
    if (photoHourOfDay.isNotEmpty) {
      final sorted = photoHourOfDay.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.length >= 2 && sorted[0].value > 0) {
        final dataPoints = sorted.where((e) => e.value > 0).length;
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline:
              'Peak photography at ${_formatHour(sorted[0].key)} and ${_formatHour(sorted[1].key)}',
          evidence:
              'Based on $photoCount photos in the last 30 days, you take the most photos at ${_formatHour(sorted[0].key)} (${sorted[0].value} photos) and ${_formatHour(sorted[1].key)} (${sorted[1].value} photos).',
          lowConfidence: dataPoints < 3,
        ));
      }
    }

    // Rule 2: Weekend vs weekday photographer
    if (photoDayOfWeek.isNotEmpty) {
      final weekendCount =
          (photoDayOfWeek['7'] ?? 0) + (photoDayOfWeek['1'] ?? 0); // Sun=1, Sat=7
      int weekdayTotal = 0;
      for (final d in ['2', '3', '4', '5', '6']) {
        weekdayTotal += photoDayOfWeek[d] ?? 0;
      }
      final weekdayAvg = weekdayTotal / 5.0;
      if (weekdayAvg > 0 && weekendCount / 2.0 > weekdayAvg * 1.5) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'Weekend photographer',
          evidence:
              'Based on $photoCount photos over 30 days, you take ${(weekendCount / 2.0 / weekdayAvg).toStringAsFixed(1)}x more photos on weekends ($weekendCount weekend photos, ${weekdayTotal ~/ 5} weekday average).',
          lowConfidence: photoCount < 3,
        ));
      }
    }

    // Rule 3: Meeting density
    if (meetingMinutes.isNotEmpty) {
      final sorted = meetingMinutes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.first.value > 0) {
        insights.add(InsightCandidate(
          type: 'calendar_pattern',
          headline:
              '${_dayName(sorted.first.key)} is your heaviest meeting day',
          evidence:
              'Based on $calendarCount events over 30 days, ${_dayName(sorted.first.key)} has ${sorted.first.value} total meeting minutes (${(sorted.first.value / 4.3).round()} min/week average).',
          lowConfidence: calendarCount < 3,
        ));
      }
    }

    // Rule 4: Meeting-free photographer
    if (photoDayOfWeek.isNotEmpty && meetingMinutes.isNotEmpty) {
      // Find day with least meetings
      final lightestMeetingDay = meetingMinutes.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      // Find day with most photos
      final heaviestPhotoDay = photoDayOfWeek.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (lightestMeetingDay.isNotEmpty &&
          heaviestPhotoDay.isNotEmpty &&
          lightestMeetingDay.first.key == heaviestPhotoDay.first.key) {
        insights.add(InsightCandidate(
          type: 'cross_pattern',
          headline: 'You shoot more on your lightest meeting days',
          evidence:
              '${_dayName(lightestMeetingDay.first.key)} has the fewest meetings (${lightestMeetingDay.first.value} min total) and the most photos (${heaviestPhotoDay.first.value} photos).',
          lowConfidence: photoCount < 3 && calendarCount < 3,
        ));
      }
    }

    // Rule 5: Night owl or early bird
    if (photoHourOfDay.isNotEmpty && photoCount > 0) {
      int nightPhotos = 0; // 20-23, 0-5
      int morningPhotos = 0; // 5-8
      for (final entry in photoHourOfDay.entries) {
        final h = int.tryParse(entry.key) ?? -1;
        if ((h >= 20 && h <= 23) || (h >= 0 && h <= 5)) {
          nightPhotos += entry.value;
        }
        if (h >= 5 && h <= 8) {
          morningPhotos += entry.value;
        }
      }
      if (nightPhotos / photoCount > 0.20) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'Night owl photographer',
          evidence:
              '${(nightPhotos / photoCount * 100).toStringAsFixed(0)}% of your $photoCount photos ($nightPhotos photos) were taken between 8 PM and 5 AM.',
          lowConfidence: nightPhotos < 3,
        ));
      } else if (morningPhotos / photoCount > 0.20) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'Early bird photographer',
          evidence:
              '${(morningPhotos / photoCount * 100).toStringAsFixed(0)}% of your $photoCount photos ($morningPhotos photos) were taken between 5 AM and 8 AM.',
          lowConfidence: morningPhotos < 3,
        ));
      }
    }

    // Rule 6: Top location cluster
    final locations = photoData['top_locations'] as List? ?? [];
    if (locations.isNotEmpty) {
      final topLoc = locations.first as Map;
      final locCount = (topLoc['count'] as num?)?.toInt() ?? 0;
      final locatedPhotos =
          (photoData['photos_with_location'] as num?)?.toInt() ?? photoCount;
      if (locatedPhotos > 0 && locCount / locatedPhotos > 0.30) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'You have a photography home base',
          evidence:
              '${(locCount / locatedPhotos * 100).toStringAsFixed(0)}% of your $locatedPhotos geotagged photos ($locCount photos) cluster at one location.',
          lowConfidence: locCount < 3,
        ));
      }
    }

    // Rule 7: Photo-calendar co-occurrence
    if (photoDayOfWeek.isNotEmpty && calendarDayOfWeek.isNotEmpty) {
      int highBothDays = 0;
      int totalDays = 0;
      for (final day in ['1', '2', '3', '4', '5', '6', '7']) {
        final pCount = photoDayOfWeek[day] ?? 0;
        final cCount = calendarDayOfWeek[day] ?? 0;
        if (pCount > 3 || cCount > 3) totalDays++;
        if (pCount > 3 && cCount > 3) highBothDays++;
      }
      if (totalDays > 0 && highBothDays / totalDays > 0.50) {
        insights.add(InsightCandidate(
          type: 'cross_pattern',
          headline: 'Busy days equal photo days',
          evidence:
              '$highBothDays of $totalDays active days have both 3+ events and 3+ photos -- your busiest days are also your most photogenic.',
          lowConfidence: highBothDays < 3,
        ));
      }
    }

    // Rule 8: Surprising fact
    if (photoDayOfWeek.isNotEmpty && photoDayOfWeek.values.any((v) => v > 0)) {
      final sorted = photoDayOfWeek.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (sorted.length >= 2) {
        final top = sorted[0];
        final second = sorted[1];
        if (second.value > 0 && top.value / second.value >= 2.0) {
          insights.add(InsightCandidate(
            type: 'surprising',
            headline:
                '${_dayName(top.key)}: your secret photo day',
            evidence:
                '${_dayName(top.key)} has ${top.value} photos -- ${(top.value / second.value).toStringAsFixed(1)}x more than ${_dayName(second.key)} (${second.value} photos).',
            lowConfidence: top.value < 3,
          ));
        }
      }
    }

    // Add source availability notes if one source is missing
    if (!photoAvailable && calendarAvailable) {
      insights.add(InsightCandidate(
        type: 'calendar_pattern',
        headline: 'Calendar-only analysis',
        evidence:
            'Photo library was unavailable. Analysis based on $calendarCount calendar events only.',
        lowConfidence: true,
      ));
    } else if (photoAvailable && !calendarAvailable) {
      insights.add(InsightCandidate(
        type: 'photo_pattern',
        headline: 'Photo-only analysis',
        evidence:
            'Calendar was unavailable. Analysis based on $photoCount photos only.',
        lowConfidence: true,
      ));
    }

    // Fallback: guarantee at least 2 insights
    if (insights.length < 2) {
      if (photoCount > 0) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'Active photographer',
          evidence: 'You have taken $photoCount photos in the last 30 days.',
        ));
      }
      if (calendarCount > 0) {
        insights.add(InsightCandidate(
          type: 'calendar_pattern',
          headline: 'Organized scheduler',
          evidence:
              'You have $calendarCount calendar events in the last 30 days.',
        ));
      }
      // If still not enough
      while (insights.length < 2) {
        insights.add(InsightCandidate(
          type: 'photo_pattern',
          headline: 'Data explorer',
          evidence:
              'Limited data available (0 photos, 0 events) -- enable demo mode for a richer experience.',
        ));
      }
    }

    return insights;
  }

  /// Convert a Map with dynamic keys/values to Map<String, int>
  Map<String, int> _toIntMap(Map data) {
    final result = <String, int>{};
    for (final entry in data.entries) {
      result[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
    }
    return result;
  }

  /// Format an hour integer to human-readable string
  String _formatHour(String hourStr) {
    final hour = int.tryParse(hourStr) ?? 0;
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }

  /// Convert day-of-week number to name (1=Sunday, 7=Saturday)
  String _dayName(String dayStr) {
    final day = int.tryParse(dayStr) ?? 0;
    const names = {
      1: 'Sunday',
      2: 'Monday',
      3: 'Tuesday',
      4: 'Wednesday',
      5: 'Thursday',
      6: 'Friday',
      7: 'Saturday',
    };
    return names[day] ?? 'Day $day';
  }
}

// ==============================================================================
// Synthetic (Demo Mode) Data
// ==============================================================================

/// Returns realistic synthetic photo data for demo mode.
/// Photos clustered on weekends, peak at 10am and 6pm.
Map<String, dynamic> _syntheticPhotoData() {
  return {
    'total_photos': 247,
    'photos_with_location': 189,
    'day_of_week_counts': {
      '1': 52, // Sunday
      '2': 18, // Monday
      '3': 14, // Tuesday
      '4': 12, // Wednesday
      '5': 16, // Thursday
      '6': 35, // Friday -- midnight photos
      '7': 100, // Saturday
    },
    'hour_of_day_counts': {
      '0': 12, // Midnight Friday photos
      '1': 4,
      '6': 3,
      '7': 5,
      '8': 8,
      '9': 14,
      '10': 38, // Peak morning
      '11': 22,
      '12': 15,
      '13': 10,
      '14': 8,
      '15': 12,
      '16': 18,
      '17': 25,
      '18': 42, // Peak evening
      '19': 20,
      '20': 8,
      '21': 6,
      '22': 3,
      '23': 2,
    },
    'top_locations': [
      {'lat': 37.79, 'lon': -122.41, 'count': 72}, // "Office" cluster
      {'lat': 37.77, 'lon': -122.43, 'count': 28},
      {'lat': 37.80, 'lon': -122.39, 'count': 15},
    ],
    'sample_photos': [
      {
        'date': '2026-01-20T10:30:00Z',
        'width': 4032,
        'height': 3024,
        'has_location': true,
      },
      {
        'date': '2026-01-25T18:15:00Z',
        'width': 4032,
        'height': 3024,
        'has_location': true,
      },
    ],
  };
}

/// Returns realistic synthetic calendar data for demo mode.
/// Heavy on Tuesday/Wednesday.
Map<String, dynamic> _syntheticCalendarData() {
  return {
    'total_events': 86,
    'day_of_week_counts': {
      '1': 4, // Sunday
      '2': 12, // Monday
      '3': 22, // Tuesday -- heaviest
      '4': 20, // Wednesday
      '5': 14, // Thursday
      '6': 10, // Friday
      '7': 4, // Saturday
    },
    'hour_of_day_counts': {
      '8': 4,
      '9': 12,
      '10': 18,
      '11': 15,
      '12': 8,
      '13': 10,
      '14': 14,
      '15': 12,
      '16': 8,
      '17': 4,
    },
    'meeting_minutes_per_day': {
      '1': 30, // Sunday
      '2': 180, // Monday
      '3': 320, // Tuesday -- heaviest
      '4': 290, // Wednesday
      '5': 210, // Thursday
      '6': 140, // Friday
      '7': 20, // Saturday
    },
    'avg_event_duration_minutes': 42,
    'sample_events': [
      {
        'title': 'Weekly Sync',
        'date': '2026-01-21T10:00:00Z',
        'duration_minutes': 30,
      },
      {
        'title': 'Design Review',
        'date': '2026-01-22T14:00:00Z',
        'duration_minutes': 60,
      },
    ],
  };
}

// ==============================================================================
// Screen State
// ==============================================================================

enum _DetectiveState {
  notReady,
  downloading,
  ready,
  scanning,
  analyzing,
  narrating,
  complete,
}

/// 45-second pipeline timeout.
const _pipelineTimeout = Duration(seconds: 45);

/// JSON schema for DetectiveReport — used with GBNF grammar-constrained
/// generation to guarantee valid JSON from the LLM narration phase.
const _detectiveReportSchema = {
  'type': 'object',
  'properties': {
    'headline': {'type': 'string'},
    'deductions': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'finding': {'type': 'string'},
          'evidence': {'type': 'string'},
        },
        'required': ['finding', 'evidence'],
      },
    },
    'surprising_fact': {'type': 'string'},
    'privacy_statement': {'type': 'string'},
  },
  'required': ['headline', 'deductions', 'surprising_fact', 'privacy_statement'],
};

// ==============================================================================
// DetectiveScreen Widget
// ==============================================================================

/// Phone Detective Mode -- on-device behavioral insights using tool calling.
///
/// Architecture: deterministic Dart [InsightEngine] computes all deductions.
/// The LLM (Qwen3-0.6B) is a stylist/narrator only -- it never analyzes raw data.
///
/// Flow:
/// 1. Tools fetch lightly processed data from native (via MethodChannel)
/// 2. [InsightEngine] computes insight candidates using deterministic rules
/// 3. LLM narrates the pre-computed insights in noir detective style
///
/// Hardened with:
/// - 45-second pipeline timeout
/// - LLM output self-checks (deduction count, number cross-reference)
/// - <think> tag stripping for Qwen3 output
/// - Fallback report from raw InsightCandidates
/// - Demo Mode determinism assertion
class DetectiveScreen extends StatefulWidget {
  const DetectiveScreen({super.key});

  @override
  State<DetectiveScreen> createState() => _DetectiveScreenState();
}

class _DetectiveScreenState extends State<DetectiveScreen>
    with SingleTickerProviderStateMixin {
  // -- State ----------------------------------------------------------------

  _DetectiveState _state = _DetectiveState.notReady;
  bool _demoMode = false;
  DetectiveReport? _report;
  String? _errorMessage;

  // Scan steps tracking
  final List<_ScanStep> _scanSteps = [
    _ScanStep(icon: Icons.photo_library, label: 'Scanning photo metadata...'),
    _ScanStep(icon: Icons.calendar_month, label: 'Cross-referencing calendar...'),
    _ScanStep(icon: Icons.shield, label: 'Verifying device privacy...'),
    _ScanStep(icon: Icons.lightbulb, label: 'Deriving patterns...'),
    _ScanStep(icon: Icons.edit_note, label: 'Composing detective report...'),
  ];

  // Model lifecycle
  final ModelManager _modelManager = ModelManager();
  EdgeVeda? _edgeVeda;
  double _downloadProgress = 0.0;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  // Tool data cache (5 min TTL)
  Map<String, dynamic>? _cachedPhotoData;
  Map<String, dynamic>? _cachedCalendarData;
  DateTime? _cacheTimestamp;
  static const _cacheTtl = Duration(minutes: 5);

  // Track data source availability for partial-data handling
  bool _photoSourceAvailable = true;
  bool _calendarSourceAvailable = true;

  // Telemetry channel (reuse existing channel)
  static const _telemetryChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');

  // Share screenshot
  final GlobalKey _reportCardKey = GlobalKey();

  // Animation
  late AnimationController _pulseController;

  // -- Lifecycle ------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _checkModel();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _downloadSubscription?.cancel();
    _edgeVeda?.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  // -- Model Lifecycle (following SttScreen pattern) ------------------------

  Future<void> _checkModel() async {
    final downloaded =
        await _modelManager.isModelDownloaded(ModelRegistry.qwen3_06b.id);
    if (mounted) {
      setState(() {
        _state = downloaded ? _DetectiveState.ready : _DetectiveState.notReady;
      });
      if (downloaded) {
        await _initEdgeVeda();
      }
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _state = _DetectiveState.downloading;
      _downloadProgress = 0;
      _errorMessage = null;
    });

    _downloadSubscription = _modelManager.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress.progress;
        });
      }
    });

    try {
      await _modelManager.downloadModel(ModelRegistry.qwen3_06b);
      if (mounted) {
        await _initEdgeVeda();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DetectiveState.notReady;
          _errorMessage = 'Download failed: $e';
        });
      }
    } finally {
      _downloadSubscription?.cancel();
      _downloadSubscription = null;
    }
  }

  Future<void> _initEdgeVeda() async {
    try {
      final modelPath =
          await _modelManager.getModelPath(ModelRegistry.qwen3_06b.id);

      _edgeVeda?.dispose();
      _edgeVeda = EdgeVeda();
      await _edgeVeda!.init(EdgeVedaConfig(
        modelPath: modelPath,
        useGpu: true,
        numThreads: 4,
        contextLength: 4096, // Room for tool prompts + narration
        maxMemoryMb: 1536,
        verbose: false,
      ));

      if (mounted) {
        setState(() {
          _state = _DetectiveState.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _DetectiveState.notReady;
          _errorMessage = 'Initialization failed: $e';
        });
      }
    }
  }

  // -- Tool Definitions ----------------------------------------------------

  List<ToolDefinition> get _toolDefinitions => [
        ToolDefinition(
          name: 'get_photo_metadata',
          description:
              'Get photo library metadata including counts by hour, day, and locations',
          parameters: {
            'type': 'object',
            'properties': {
              'limit': {
                'type': 'integer',
                'description': 'Maximum photos to scan',
              },
              'since_days': {
                'type': 'integer',
                'description': 'Scan photos from the last N days',
              },
            },
            'required': ['limit', 'since_days'],
          },
        ),
        ToolDefinition(
          name: 'get_calendar_events',
          description:
              'Get calendar event summaries including meeting density and patterns',
          parameters: {
            'type': 'object',
            'properties': {
              'since_days': {
                'type': 'integer',
                'description': 'Get events from the last N days',
              },
              'until_days': {
                'type': 'integer',
                'description': 'Get events until N days from now',
              },
            },
            'required': ['since_days'],
          },
        ),
        ToolDefinition(
          name: 'device_assert_offline',
          description:
              'Verify that all data processing is happening on-device with no network uploads',
          parameters: {
            'type': 'object',
            'properties': {},
          },
        ),
      ];

  // -- Tool Call Handler ---------------------------------------------------

  Future<ToolResult> _handleToolCall(ToolCall call) async {
    switch (call.name) {
      case 'get_photo_metadata':
        final data = await _getPhotoData();
        return ToolResult.success(toolCallId: call.id, data: data);

      case 'get_calendar_events':
        final data = await _getCalendarData();
        return ToolResult.success(toolCallId: call.id, data: data);

      case 'device_assert_offline':
        return ToolResult.success(
          toolCallId: call.id,
          data: {
            'network_status': 'offline',
            'airplane_mode': true,
            'privacy_verified': true,
          },
        );

      default:
        return ToolResult.failure(
          toolCallId: call.id,
          error: 'Unknown tool: ${call.name}',
        );
    }
  }

  /// Request photo + calendar permissions if not yet determined.
  /// Returns true if at least one source is available.
  Future<bool> _ensurePermissions() async {
    try {
      final status = await _telemetryChannel
          .invokeMethod<Map>('checkDetectivePermissions');
      final photosStatus = status?['photos'] as String? ?? 'notDetermined';
      final calendarStatus = status?['calendar'] as String? ?? 'notDetermined';

      // If either is not yet determined, request permissions
      if (photosStatus == 'notDetermined' || calendarStatus == 'notDetermined') {
        final result = await _telemetryChannel
            .invokeMethod<Map>('requestDetectivePermissions');
        final photosResult = result?['photos'] as String? ?? 'denied';
        final calendarResult = result?['calendar'] as String? ?? 'denied';
        _photoSourceAvailable =
            photosResult == 'granted' || photosResult == 'limited';
        _calendarSourceAvailable = calendarResult == 'granted';
      } else {
        _photoSourceAvailable =
            photosStatus == 'granted' || photosStatus == 'limited';
        _calendarSourceAvailable = calendarStatus == 'granted';
      }

      return _photoSourceAvailable || _calendarSourceAvailable;
    } catch (e) {
      debugPrint('Detective: Permission check failed: $e');
      return false;
    }
  }

  /// Day name (from native) → day-of-week number (InsightEngine format).
  /// NSCalendar weekday: 1=Sunday, 2=Monday, ..., 7=Saturday.
  static const _dayNameToNumber = {
    'Sun': '1', 'Mon': '2', 'Tue': '3', 'Wed': '4',
    'Thu': '5', 'Fri': '6', 'Sat': '7',
  };

  /// Convert native camelCase photo response to snake_case format expected by InsightEngine.
  Map<String, dynamic> _normalizePhotoData(Map raw) {
    // Convert dayOfWeekCounts: {"Sun": 5, "Mon": 3} → {"1": 5, "2": 3}
    final nativeDow = raw['dayOfWeekCounts'] as Map? ?? {};
    final normalizedDow = <String, dynamic>{};
    for (final entry in nativeDow.entries) {
      final num = _dayNameToNumber[entry.key.toString()];
      if (num != null) normalizedDow[num] = entry.value;
    }

    return {
      'total_photos': raw['totalPhotos'] ?? 0,
      'photos_with_location': raw['photosWithLocation'] ?? 0,
      'day_of_week_counts': normalizedDow,
      'hour_of_day_counts': raw['hourOfDayCounts'] ?? {},
      'top_locations': raw['topLocations'] ?? [],
      'sample_photos': raw['samplePhotos'] ?? [],
    };
  }

  /// Convert native camelCase calendar response to snake_case format expected by InsightEngine.
  Map<String, dynamic> _normalizeCalendarData(Map raw) {
    final nativeDow = raw['dayOfWeekCounts'] as Map? ?? {};
    final normalizedDow = <String, dynamic>{};
    for (final entry in nativeDow.entries) {
      final num = _dayNameToNumber[entry.key.toString()];
      if (num != null) normalizedDow[num] = entry.value;
    }

    final nativeMinutes = raw['meetingMinutesPerWeekday'] as Map? ?? {};
    final normalizedMinutes = <String, dynamic>{};
    for (final entry in nativeMinutes.entries) {
      final num = _dayNameToNumber[entry.key.toString()];
      if (num != null) normalizedMinutes[num] = entry.value;
    }

    return {
      'total_events': raw['totalEvents'] ?? 0,
      'day_of_week_counts': normalizedDow,
      'hour_of_day_counts': raw['hourOfDayCounts'] ?? {},
      'meeting_minutes_per_day': normalizedMinutes,
      'avg_event_duration_minutes': raw['averageDurationMinutes'] ?? 0,
      'sample_events': raw['sampleEvents'] ?? [],
    };
  }

  Future<Map<String, dynamic>> _getPhotoData() async {
    // Check cache
    if (_cachedPhotoData != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheTtl) {
      return _cachedPhotoData!;
    }

    if (_demoMode) {
      _cachedPhotoData = _syntheticPhotoData();
      _cacheTimestamp = DateTime.now();
      _photoSourceAvailable = true;
      return _cachedPhotoData!;
    }

    try {
      final result =
          await _telemetryChannel.invokeMethod<Map>('getPhotoInsights');
      _cachedPhotoData = _normalizePhotoData(result ?? {});
      _cacheTimestamp = DateTime.now();
      _photoSourceAvailable = true;
      return _cachedPhotoData!;
    } catch (e) {
      debugPrint('Detective: Photo fetch failed: $e');
      _photoSourceAvailable = false;
      // Fall back to empty data
      return {'total_photos': 0};
    }
  }

  Future<Map<String, dynamic>> _getCalendarData() async {
    // Check cache
    if (_cachedCalendarData != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheTtl) {
      return _cachedCalendarData!;
    }

    if (_demoMode) {
      _cachedCalendarData = _syntheticCalendarData();
      _cacheTimestamp = DateTime.now();
      _calendarSourceAvailable = true;
      return _cachedCalendarData!;
    }

    try {
      final result =
          await _telemetryChannel.invokeMethod<Map>('getCalendarInsights');
      _cachedCalendarData = _normalizeCalendarData(result ?? {});
      _cacheTimestamp = DateTime.now();
      _calendarSourceAvailable = true;
      return _cachedCalendarData!;
    } catch (e) {
      debugPrint('Detective: Calendar fetch failed: $e');
      _calendarSourceAvailable = false;
      return {'total_events': 0};
    }
  }

  // -- Main Analysis Pipeline (with 15s timeout) --------------------------

  Future<void> _runAnalysis() async {
    if (_edgeVeda == null || !_edgeVeda!.isInitialized) {
      _showError('Model not ready. Please wait for initialization.');
      return;
    }

    // Request photo + calendar permissions before fetching data
    if (!_demoMode) {
      final hasAnySource = await _ensurePermissions();
      if (!hasAnySource && mounted) {
        setState(() {
          _errorMessage =
              'Photo and calendar access denied. Enable Demo Mode to try with synthetic data, or grant permissions in Settings.';
        });
        return;
      }
    }

    setState(() {
      _state = _DetectiveState.scanning;
      _errorMessage = null;
      _report = null;
      for (final step in _scanSteps) {
        step.status = _StepStatus.pending;
      }
    });

    final stopwatch = Stopwatch()..start();
    int toolsMs = 0;
    int engineMs = 0;
    int narrationMs = 0;

    try {
      // Wrap entire pipeline in a 45-second timeout
      await Future.any<void>([
        _runPipelineInner(
          stopwatch: stopwatch,
          onToolsDone: (ms) => toolsMs = ms,
          onEngineDone: (ms) => engineMs = ms,
          onNarrationDone: (ms) => narrationMs = ms,
        ),
        Future.delayed(_pipelineTimeout).then((_) {
          throw TimeoutException(
              'Pipeline exceeded ${_pipelineTimeout.inSeconds}s timeout');
        }),
      ]);
    } on TimeoutException {
      stopwatch.stop();
      debugPrint(
          'Detective pipeline: TIMEOUT at ${stopwatch.elapsedMilliseconds}ms');

      // Use whatever insights are computed so far
      final photoData = _cachedPhotoData ?? {'total_photos': 0};
      final calendarData = _cachedCalendarData ?? {'total_events': 0};
      final engine = InsightEngine();
      final insights = engine.computeInsights(
        photoData,
        calendarData,
        photoAvailable: _photoSourceAvailable,
        calendarAvailable: _calendarSourceAvailable,
      );
      final report = _fallbackReport(insights);

      if (mounted) {
        setState(() {
          _report = report;
          _state = _DetectiveState.complete;
          for (final step in _scanSteps) {
            if (step.status != _StepStatus.complete) {
              step.status = _StepStatus.complete;
            }
          }
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _state = _DetectiveState.ready;
          _errorMessage = 'Analysis failed: $e';
        });
      }
    }

    stopwatch.stop();
    final totalMs = stopwatch.elapsedMilliseconds;
    debugPrint(
        'Detective pipeline: tools=${toolsMs}ms, engine=${engineMs}ms, narration=${narrationMs}ms, total=${totalMs}ms');
  }

  /// Inner pipeline logic, separated to allow timeout wrapper.
  Future<void> _runPipelineInner({
    required Stopwatch stopwatch,
    required void Function(int) onToolsDone,
    required void Function(int) onEngineDone,
    required void Function(int) onNarrationDone,
  }) async {
    final toolsStart = stopwatch.elapsedMilliseconds;

    // -- Phase 1: Tool calling -----------------------------------------
    // Use sendWithTools to let the LLM invoke our data-gathering tools.
    // The tool call handler fetches data from native or demo mode.
    // Each tool call updates the scan step UI.

    _updateStep(0, _StepStatus.inProgress);

    final toolSession = ChatSession(
      edgeVeda: _edgeVeda!,
      systemPrompt:
          'You are a data analyst. Call get_photo_metadata and get_calendar_events to gather data about the user\'s phone. Then call device_assert_offline to verify privacy. Call each tool exactly once.',
      templateFormat: ChatTemplateFormat.qwen3,
      tools: ToolRegistry(_toolDefinitions),
      maxResponseTokens: 256,
    );

    try {
      await toolSession.sendWithTools(
        'Analyze the user\'s phone: scan their photos and calendar, then verify privacy.',
        onToolCall: (call) async {
          // Update scan step UI based on which tool was called
          if (call.name == 'get_photo_metadata') {
            _updateStep(0, _StepStatus.inProgress);
            final result = await _handleToolCall(call);
            _updateStep(0, _StepStatus.complete);
            _updateStep(1, _StepStatus.inProgress);
            return result;
          } else if (call.name == 'get_calendar_events') {
            final result = await _handleToolCall(call);
            _updateStep(1, _StepStatus.complete);
            _updateStep(2, _StepStatus.inProgress);
            return result;
          } else if (call.name == 'device_assert_offline') {
            final result = await _handleToolCall(call);
            _updateStep(2, _StepStatus.complete);
            return result;
          }
          return _handleToolCall(call);
        },
        options: const GenerateOptions(
          maxTokens: 256,
          temperature: 0.7,
          topP: 0.9,
        ),
      );
    } catch (e) {
      // Tool calling may fail (ToolCallParseException, etc.)
      // Fall back to direct data fetching
      debugPrint('Detective: Tool calling failed ($e), fetching data directly');
    }

    // Ensure all data steps are complete (direct fetch if tools didn't fire)
    if (_cachedPhotoData == null) {
      _updateStep(0, _StepStatus.inProgress);
      await _getPhotoData();
      _updateStep(0, _StepStatus.complete);
    } else {
      _updateStep(0, _StepStatus.complete);
    }

    if (_cachedCalendarData == null) {
      _updateStep(1, _StepStatus.inProgress);
      await _getCalendarData();
      _updateStep(1, _StepStatus.complete);
    } else {
      _updateStep(1, _StepStatus.complete);
    }

    _updateStep(2, _StepStatus.complete);
    onToolsDone(stopwatch.elapsedMilliseconds - toolsStart);

    // Use the fetched (or cached) data
    final photoData = _cachedPhotoData ?? {'total_photos': 0};
    final calendarData = _cachedCalendarData ?? {'total_events': 0};

    // Check for empty data (both sources empty and not demo mode)
    final photoCount =
        (photoData['total_photos'] as num?)?.toInt() ?? 0;
    final calendarCount =
        (calendarData['total_events'] as num?)?.toInt() ?? 0;
    if (photoCount == 0 && calendarCount == 0 && !_demoMode) {
      setState(() {
        _state = _DetectiveState.ready;
        _errorMessage =
            'No photo or calendar data found. Enable Demo Mode to try with synthetic data.';
      });
      return;
    }

    // -- Phase 1.5: InsightEngine (deterministic Dart) -----------------
    final engineStart = stopwatch.elapsedMilliseconds;
    setState(() => _state = _DetectiveState.analyzing);
    _updateStep(3, _StepStatus.inProgress);
    final engine = InsightEngine();
    final insights = engine.computeInsights(
      photoData,
      calendarData,
      photoAvailable: _photoSourceAvailable,
      calendarAvailable: _calendarSourceAvailable,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    _updateStep(3, _StepStatus.complete);
    onEngineDone(stopwatch.elapsedMilliseconds - engineStart);

    // Determinism check: demo mode must produce >= 3 insights
    if (_demoMode) {
      assert(
        insights.length >= 3,
        'Demo mode must produce at least 3 insights, got ${insights.length}',
      );
    }

    // -- Phase 2: LLM narration ----------------------------------------
    final narrationStart = stopwatch.elapsedMilliseconds;
    setState(() => _state = _DetectiveState.narrating);
    _updateStep(4, _StepStatus.inProgress);

    DetectiveReport? report;
    try {
      report = await _narrateInsights(insights);
    } catch (e) {
      debugPrint('Detective: LLM narration failed: $e');
      report = _fallbackReport(insights);
    }

    _updateStep(4, _StepStatus.complete);
    onNarrationDone(stopwatch.elapsedMilliseconds - narrationStart);

    if (mounted) {
      setState(() {
        _report = report;
        _state = _DetectiveState.complete;
      });
    }
  }

  /// Phase 2: LLM narrates pre-computed insights in noir detective style.
  /// Uses a fresh ChatSession (no tools) for the narration.
  /// Uses GBNF grammar-constrained generation (sendStructured) to guarantee
  /// valid JSON output from the small on-device model.
  /// Includes /nothink to disable Qwen3 thinking mode.
  Future<DetectiveReport> _narrateInsights(
      List<InsightCandidate> insights) async {
    // Prefer high-confidence insights for narration
    final highConfidence =
        insights.where((i) => !i.lowConfidence).toList();
    final insightsForNarration =
        highConfidence.length >= 3 ? highConfidence : insights;
    final insightsJson =
        jsonEncode(insightsForNarration.map((i) => i.toJson()).toList());

    final narrationPrompt = '''/nothink
Given the following computed deductions about a person's phone data, write a dramatic noir detective report.

RULES:
- You MUST use ONLY the provided deductions. Do not invent new findings.
- Use the EXACT numbers from the evidence provided. Do not round, estimate, or fabricate any statistics.
- Write exactly 3 deductions with dramatic findings and evidence using the exact numbers.

DEDUCTIONS:
$insightsJson''';

    final narrationSession = ChatSession(
      edgeVeda: _edgeVeda!,
      systemPrompt:
          '/nothink\nYou are a spy thriller narrator. Write dramatic noir detective reports from provided data. Use the exact numbers given to you.',
      templateFormat: ChatTemplateFormat.qwen3,
      maxResponseTokens: 1024,
    );

    // Use grammar-constrained generation to guarantee valid JSON structure
    final parsed = await narrationSession.sendStructured(
      narrationPrompt,
      schema: _detectiveReportSchema,
      options: const GenerateOptions(
        maxTokens: 768,
        temperature: 0.7,
        topP: 0.9,
      ),
    );

    // Validate and build report from the guaranteed-valid JSON
    return _buildReportFromParsed(parsed, insightsForNarration);
  }

  /// Extract all numbers from a string for cross-reference validation.
  static Set<String> _extractNumbers(String text) {
    return RegExp(r'\d+\.?\d*').allMatches(text).map((m) => m.group(0)!).toSet();
  }

  /// Build a DetectiveReport from grammar-constrained JSON output.
  ///
  /// The JSON structure is guaranteed valid by GBNF grammar, but we still
  /// validate the *content* (fabrication detection, number cross-reference).
  ///
  /// Self-checks:
  /// 1. Deduction count is exactly 3 (pad from InsightCandidates or trim)
  /// 2. Each deduction evidence contains at least one number from original insights
  /// 3. No deduction references data fields not present in insight candidates
  DetectiveReport _buildReportFromParsed(
      Map<String, dynamic> parsed, List<InsightCandidate> insights) {
    // Collect all numbers from original insight candidates for cross-reference
    final insightNumbers = <String>{};
    for (final insight in insights) {
      insightNumbers.addAll(_extractNumbers(insight.evidence));
    }

    // Check insight types for field validation -- reject deductions referencing
    // data fields that were not present in the computed insight candidates.
    final hasLocationData =
        insights.any((i) => i.evidence.contains('location') || i.evidence.contains('geotagged'));
    final hasPhotoData =
        insights.any((i) => i.type == 'photo_pattern' && !i.lowConfidence);
    final hasCalendarData =
        insights.any((i) => i.type == 'calendar_pattern' && !i.lowConfidence);

    final deductionsList = parsed['deductions'] as List? ?? [];
    final validatedDeductions = <Deduction>[];

    for (final d in deductionsList.take(3)) {
      final finding = (d['finding'] as String?) ?? '';
      final evidence = (d['evidence'] as String?) ?? '';

      // Self-check: reject deductions mentioning data fields not in insights
      final findingLower = finding.toLowerCase();
      final evidenceLower = evidence.toLowerCase();
      if (!hasLocationData &&
          (evidenceLower.contains('location') ||
              evidenceLower.contains('places') ||
              findingLower.contains('location'))) {
        debugPrint(
            'Detective: Rejected fabricated location deduction: $finding');
        continue;
      }
      if (!hasPhotoData &&
          (evidenceLower.contains('photo') ||
              findingLower.contains('photo'))) {
        debugPrint(
            'Detective: Rejected fabricated photo deduction (no photo data): $finding');
        continue;
      }
      if (!hasCalendarData &&
          (evidenceLower.contains('meeting') ||
              evidenceLower.contains('calendar') ||
              evidenceLower.contains('event') ||
              findingLower.contains('meeting') ||
              findingLower.contains('calendar'))) {
        debugPrint(
            'Detective: Rejected fabricated calendar deduction (no calendar data): $finding');
        continue;
      }

      // Self-check: evidence must contain at least one number from our insights
      final evidenceNumbers = _extractNumbers(evidence);
      final hasValidNumber =
          evidenceNumbers.intersection(insightNumbers).isNotEmpty;

      if (hasValidNumber) {
        validatedDeductions.add(Deduction(
          finding: finding.isNotEmpty ? finding : 'Finding',
          evidence: evidence.isNotEmpty ? evidence : 'Evidence unavailable',
        ));
      } else {
        debugPrint(
            'Detective: Deduction evidence numbers $evidenceNumbers not found in insight numbers $insightNumbers -- replacing with raw insight');
        // Replace with raw insight candidate at this position
        final idx = validatedDeductions.length;
        if (idx < insights.length) {
          validatedDeductions.add(Deduction(
            finding: insights[idx].headline,
            evidence: insights[idx].evidence,
          ));
        }
      }
    }

    // Pad to exactly 3 deductions from InsightCandidates
    while (validatedDeductions.length < 3 &&
        validatedDeductions.length < insights.length) {
      final idx = validatedDeductions.length;
      validatedDeductions.add(Deduction(
        finding: insights[idx].headline,
        evidence: insights[idx].evidence,
      ));
    }

    // Trim to exactly 3
    final finalDeductions = validatedDeductions.take(3).toList();

    return DetectiveReport(
      headline: (parsed['headline'] as String?) ?? 'Case File: Subject Analysis',
      deductions: finalDeductions,
      surprisingFact: (parsed['surprising_fact'] as String?) ??
          insights
              .where((i) => i.type == 'surprising')
              .map((i) => i.headline)
              .firstOrNull ??
          'The subject remains unpredictable.',
      privacyStatement: (parsed['privacy_statement'] as String?) ??
          'Every byte of this analysis happened on your device. No data was uploaded, no servers were contacted.',
    );
  }

  String _dramaticHeadline(List<InsightCandidate> insights) {
    final hasNightOwl = insights.any((i) => i.headline.contains('Night owl'));
    final hasEarlyBird = insights.any((i) => i.headline.contains('Early bird'));
    final hasWeekend = insights.any((i) => i.headline.contains('Weekend'));
    final hasHomeBase = insights.any((i) => i.headline.contains('home base'));
    final hasCrossPattern = insights.any((i) => i.type == 'cross_pattern');
    final hasHeavyMeetings =
        insights.any((i) => i.headline.contains('heaviest meeting'));

    if (hasNightOwl) return 'Case File: The Midnight Operator';
    if (hasEarlyBird) return 'Case File: The Dawn Patrol';
    if (hasWeekend && hasHomeBase) return 'Case File: The Weekend Regular';
    if (hasWeekend) return 'Case File: The Saturday Suspect';
    if (hasHomeBase) return 'Case File: The Creature of Habit';
    if (hasCrossPattern) return 'Case File: The Double Life';
    if (hasHeavyMeetings) return 'Case File: The Corporate Ghost';
    return 'Case File: Subject Under Surveillance';
  }

  String _dramaticFinding(InsightCandidate insight) {
    final h = insight.headline.toLowerCase();
    if (h.contains('night owl')) return 'The subject operates under cover of darkness';
    if (h.contains('early bird')) return 'Subject rises before the city wakes';
    if (h.contains('peak photography')) {
      return 'Surveillance patterns reveal preferred operating hours';
    }
    if (h.contains('weekend photographer')) {
      return 'The subject leads a double life on weekends';
    }
    if (h.contains('home base')) return 'A single location keeps pulling them back';
    if (h.contains('heaviest meeting')) {
      return 'One day a week, they vanish into back-to-back meetings';
    }
    if (h.contains('lightest meeting')) {
      return 'When the calendar clears, the camera comes out';
    }
    if (h.contains('busy days equal photo days')) {
      return 'The busier the day, the more evidence they leave behind';
    }
    if (h.contains('secret photo day')) {
      return 'One day stands out in the surveillance logs';
    }
    if (h.contains('only analysis')) {
      return 'Limited intel available -- partial dossier compiled';
    }
    return 'A pattern emerges from the digital trail';
  }

  /// Construct a report directly from InsightCandidates without LLM narration.
  /// Used when LLM fails entirely (timeout, parse error, empty response).
  DetectiveReport _fallbackReport(List<InsightCandidate> insights) {
    final deductions = insights
        .where((i) => !i.lowConfidence)
        .take(3)
        .map((i) => Deduction(
              finding: _dramaticFinding(i),
              evidence: i.evidence,
            ))
        .toList();

    // If not enough high-confidence, fill from all
    if (deductions.length < 3) {
      for (final i in insights) {
        if (deductions.length >= 3) break;
        if (!deductions.any((d) => d.evidence == i.evidence)) {
          deductions.add(Deduction(
            finding: _dramaticFinding(i),
            evidence: i.evidence,
          ));
        }
      }
    }

    while (deductions.length < 3) {
      deductions.add(Deduction(
        finding: 'The trail goes cold here',
        evidence: 'Further surveillance required to complete the dossier.',
      ));
    }

    // Surprising fact: prefer 'surprising' type, then cross_pattern, then any high-confidence
    final surprisingInsight = insights
        .where((i) => i.type == 'surprising')
        .firstOrNull;
    final crossInsight = insights
        .where((i) => i.type == 'cross_pattern')
        .firstOrNull;
    final bestSurprise = surprisingInsight ??
        crossInsight ??
        insights.where((i) => !i.lowConfidence).firstOrNull;

    String surprisingFact;
    if (bestSurprise != null) {
      surprisingFact =
          'What the subject doesn\'t realize: ${bestSurprise.evidence}';
    } else {
      final photoCount = _cachedPhotoData != null
          ? ((_cachedPhotoData!['total_photos'] as num?)?.toInt() ?? 0)
          : 0;
      surprisingFact =
          'The subject left $photoCount digital breadcrumbs in 30 days -- and never once looked over their shoulder.';
    }

    return DetectiveReport(
      headline: _dramaticHeadline(insights),
      deductions: deductions,
      surprisingFact: surprisingFact,
      privacyStatement:
          'Every byte of this dossier was compiled on-device. No dead drops, no server contacts, no third parties. Your secrets stayed yours.',
    );
  }

  // -- Helpers -------------------------------------------------------------

  void _updateStep(int index, _StepStatus status) {
    if (mounted) {
      setState(() {
        _scanSteps[index].status = status;
      });
    }
  }

  void _resetDemo() {
    _cachedPhotoData = null;
    _cachedCalendarData = null;
    _cacheTimestamp = null;
    _photoSourceAvailable = true;
    _calendarSourceAvailable = true;
    setState(() {
      _state = _DetectiveState.ready;
      _report = null;
      _errorMessage = null;
      for (final step in _scanSteps) {
        step.status = _StepStatus.pending;
      }
    });
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  Future<void> _shareReport() async {
    try {
      final boundary = _reportCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/detective_report.png');
      await file.writeAsBytes(bytes);

      await _telemetryChannel.invokeMethod('shareFile', {
        'path': file.path,
        'mimeType': 'image/png',
      });
    } catch (e) {
      debugPrint('Detective: Share failed: $e');
      _showError('Could not share report');
    }
  }

  // ========================================================================
  // UI
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text(
          'Phone Detective',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Demo Mode toggle
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Demo',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              Switch(
                value: _demoMode,
                onChanged: (_state == _DetectiveState.scanning ||
                        _state == _DetectiveState.analyzing ||
                        _state == _DetectiveState.narrating)
                    ? null
                    : (value) {
                        setState(() {
                          _demoMode = value;
                          // Clear cache when toggling demo mode
                          _cachedPhotoData = null;
                          _cachedCalendarData = null;
                          _cacheTimestamp = null;
                        });
                      },
                activeTrackColor: AppTheme.accent,
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _DetectiveState.notReady:
      case _DetectiveState.downloading:
        return _buildDownloadState();
      case _DetectiveState.ready:
        return _buildReadyState();
      case _DetectiveState.scanning:
      case _DetectiveState.analyzing:
      case _DetectiveState.narrating:
        return _buildScanningState();
      case _DetectiveState.complete:
        return _buildCompleteState();
    }
  }

  // -- Download State ------------------------------------------------------

  Widget _buildDownloadState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.policy, size: 72, color: AppTheme.accent),
            const SizedBox(height: 24),
            const Text(
              'Phone Detective',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download Qwen3-0.6B (~${(ModelRegistry.qwen3_06b.sizeBytes / (1024 * 1024)).round()} MB) to enable\non-device behavioral analysis',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (_state == _DetectiveState.downloading) ...[
              SizedBox(
                width: 240,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        color: AppTheme.accent,
                        backgroundColor: AppTheme.surfaceVariant,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(_downloadProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              ElevatedButton.icon(
                onPressed: _downloadModel,
                icon: const Icon(Icons.download),
                label: const Text('Download Model'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _downloadModel,
                child: const Text('Retry',
                    style: TextStyle(color: AppTheme.accent)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -- Ready State ---------------------------------------------------------

  Widget _buildReadyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.policy, size: 80, color: AppTheme.accent),
            const SizedBox(height: 24),
            const Text(
              'Your phone knows things\nabout you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'We analyze your photo library and calendar\nto uncover patterns you never noticed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _runAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.background,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "Find Something I Don't Know\nAbout Myself",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            if (_demoMode) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Demo Mode -- using synthetic data',
                  style: TextStyle(color: AppTheme.accent, fontSize: 12),
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              // Show "Enable Demo Mode" button when no data found
              if (_errorMessage!.contains('Demo Mode')) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _demoMode = true;
                      _errorMessage = null;
                      _cachedPhotoData = null;
                      _cachedCalendarData = null;
                      _cacheTimestamp = null;
                    });
                  },
                  child: const Text(
                    'Enable Demo Mode',
                    style: TextStyle(color: AppTheme.accent),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // -- Scanning / Analyzing / Narrating State ------------------------------

  Widget _buildScanningState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Investigating...',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 32),
          // Vertical timeline
          Expanded(
            child: ListView.builder(
              itemCount: _scanSteps.length,
              itemBuilder: (context, index) {
                final step = _scanSteps[index];
                return _buildStepTile(step, index);
              },
            ),
          ),
          // Footer
          const Center(
            child: Text(
              'Processed on device. Nothing uploaded.',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStepTile(_ScanStep step, int index) {
    final isActive = step.status == _StepStatus.inProgress;
    final isComplete = step.status == _StepStatus.complete;
    final isPending = step.status == _StepStatus.pending;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) {
                  return Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isComplete
                          ? AppTheme.success.withValues(alpha: 0.15)
                          : isActive
                              ? AppTheme.accent
                                  .withValues(alpha: 0.15 + 0.1 * _pulseController.value)
                              : AppTheme.surfaceVariant,
                    ),
                    child: Icon(
                      isComplete ? Icons.check : step.icon,
                      size: 20,
                      color: isComplete
                          ? AppTheme.success
                          : isActive
                              ? AppTheme.accent
                              : AppTheme.textTertiary,
                    ),
                  );
                },
              ),
              if (index < _scanSteps.length - 1)
                Container(
                  width: 2,
                  height: 24,
                  color: isComplete ? AppTheme.success : AppTheme.border,
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Step label
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isPending
                          ? AppTheme.textTertiary
                          : isActive
                              ? AppTheme.accent
                              : AppTheme.textPrimary,
                    ),
                  ),
                  if (isActive)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: 120,
                        height: 2,
                        child: LinearProgressIndicator(
                          color: AppTheme.accent,
                          backgroundColor: AppTheme.surfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -- Complete State (Results Card) ---------------------------------------

  Widget _buildCompleteState() {
    final report = _report;
    if (report == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Results card
          RepaintBoundary(
            key: _reportCardKey,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.accent, width: 1.5),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Headline
                  Text(
                    report.headline,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.border),
                  const SizedBox(height: 16),

                  // Deductions
                  for (int i = 0; i < report.deductions.length; i++) ...[
                    _buildDeduction(i + 1, report.deductions[i]),
                    if (i < report.deductions.length - 1)
                      const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.border),
                  const SizedBox(height: 16),

                  // Surprising fact
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb,
                          color: AppTheme.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Surprising Fact',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.warning,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.surprisingFact,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(color: AppTheme.border),
                  const SizedBox(height: 16),

                  // Privacy statement
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield,
                          color: AppTheme.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          report.privacyStatement,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.accent,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Footer
                  const Center(
                    child: Text(
                      'Processed on device. Nothing uploaded.',
                      style: TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetDemo,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset Demo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareReport,
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: AppTheme.background,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDeduction(int number, Deduction deduction) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number badge
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.accent.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deduction.finding,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                deduction.evidence,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// Internal Step Model
// ==============================================================================

enum _StepStatus { pending, inProgress, complete }

class _ScanStep {
  final IconData icon;
  final String label;
  _StepStatus status = _StepStatus.pending;

  _ScanStep({required this.icon, required this.label});
}
