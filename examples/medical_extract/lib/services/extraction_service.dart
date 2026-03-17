import 'dart:convert';
import 'package:edge_veda/edge_veda.dart';

/// JSON schema for prescription extraction
const prescriptionSchema = {
  'type': 'object',
  'properties': {
    'drug_name': {'type': 'string', 'description': 'Name of the medication'},
    'dosage': {'type': 'string', 'description': 'Dosage amount and form (e.g., 500mg tablet)'},
    'frequency': {'type': 'string', 'description': 'How often to take (e.g., twice daily)'},
    'prescriber': {'type': 'string', 'description': 'Name of prescribing physician'},
    'date': {'type': 'string', 'description': 'Date of prescription (YYYY-MM-DD)'},
  },
  'required': ['drug_name', 'dosage', 'frequency'],
};

/// JSON schema for lab report extraction
const labReportSchema = {
  'type': 'object',
  'properties': {
    'tests': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'test_name': {'type': 'string', 'description': 'Name of the lab test'},
          'value': {'type': 'string', 'description': 'Test result value'},
          'unit': {'type': 'string', 'description': 'Unit of measurement'},
          'reference_range': {'type': 'string', 'description': 'Normal reference range'},
          'flag': {
            'type': 'string',
            'enum': ['normal', 'high', 'low', 'critical'],
            'description': 'Flag indicating if result is normal, high, low, or critical',
          },
        },
        'required': ['test_name', 'value'],
      },
    },
  },
  'required': ['tests'],
};

/// Extraction mode
enum ExtractionMode { prescription, labReport }

/// Service for medical document extraction using on-device AI.
class ExtractionService {
  EdgeVeda? _veda;
  ChatSession? _chatSession;
  RagPipeline? _ragPipeline;
  String? _lastDocumentText;

  bool get isReady => _veda != null;

  /// Initialize the AI engine with MedGemma model.
  Future<void> init({
    required void Function(String) onStatus,
    required void Function(double) onProgress,
  }) async {
    onStatus('Downloading MedGemma model...');

    final modelManager = ModelManager();
    final modelPath = await modelManager.downloadModel(
      ModelRegistry.medGemma2b,
      onProgress: (p) => onProgress(p.progress * 0.8),
    );

    onStatus('Downloading embedding model...');
    final embeddingPath = await modelManager.downloadModel(
      ModelRegistry.allMiniLmL6V2,
      onProgress: (p) => onProgress(0.8 + p.progress * 0.15),
    );

    onStatus('Loading models...');
    _veda = await EdgeVeda.create(EdgeVedaConfig(modelPath: modelPath));

    _ragPipeline = RagPipeline(
      config: RagConfig(
        chunkSize: 512,
        chunkOverlap: 64,
        topK: 4,
      ),
    );
    await _ragPipeline!.init(embeddingModelPath: embeddingPath);

    onProgress(1.0);
    onStatus('Ready');
  }

  /// Extract structured data from document text.
  Future<Map<String, dynamic>> extract(
    String documentText,
    ExtractionMode mode,
  ) async {
    _lastDocumentText = documentText;
    _chatSession = _veda!.createChatSession(
      systemPrompt: _systemPrompt(mode),
    );

    // Index document for follow-up Q&A
    await _ragPipeline?.indexText(documentText, source: 'document');

    final schema = mode == ExtractionMode.prescription
        ? prescriptionSchema
        : labReportSchema;

    final prompt = mode == ExtractionMode.prescription
        ? 'Extract the prescription details from this medical document:\n\n$documentText'
        : 'Extract all lab test results from this medical document:\n\n$documentText';

    final response = await _chatSession!.sendStructured(
      prompt,
      schema: schema,
    );

    try {
      return jsonDecode(response.text) as Map<String, dynamic>;
    } catch (_) {
      return {'error': 'Failed to parse extraction result', 'raw': response.text};
    }
  }

  /// Ask a follow-up question about the extracted document using RAG.
  Stream<TokenChunk> askFollowUp(String question) async* {
    if (_ragPipeline == null || _chatSession == null) return;

    final context = await _ragPipeline!.retrieve(question);
    final augmentedPrompt =
        'Based on the medical document context below, answer the question.\n\n'
        'Context:\n${context.map((c) => c.text).join('\n---\n')}\n\n'
        'Question: $question';

    yield* _chatSession!.sendStream(augmentedPrompt);
  }

  String _systemPrompt(ExtractionMode mode) {
    if (mode == ExtractionMode.prescription) {
      return 'You are a medical document extraction assistant. '
          'Extract prescription details from the provided text. '
          'Return structured JSON with drug_name, dosage, frequency, prescriber, and date. '
          'Be precise and only extract information that is explicitly stated.';
    }
    return 'You are a medical document extraction assistant. '
        'Extract lab test results from the provided text. '
        'Return structured JSON with an array of tests, each containing '
        'test_name, value, unit, reference_range, and flag (normal/high/low/critical). '
        'Be precise and only extract information that is explicitly stated.';
  }

  void dispose() {
    _chatSession?.dispose();
    _ragPipeline?.dispose();
    _veda?.dispose();
  }
}
