/// Edge Veda SDK - On-device LLM inference for Flutter
///
/// Example usage:
/// ```dart
/// import 'package:edge_veda/edge_veda.dart';
///
/// final edgeVeda = EdgeVeda();
/// await edgeVeda.init(EdgeVedaConfig(modelPath: '/path/to/model.gguf'));
/// final response = await edgeVeda.generate('Hello, world!');
/// print(response.text);
/// await edgeVeda.dispose();
/// ```
///
/// ## Features
///
/// - On-device LLM inference with llama.cpp and Metal acceleration
/// - Streaming token-by-token generation with cancellation support
/// - Model download with progress tracking and caching
/// - Memory-safe operations with configurable limits
/// - Zero server costs and 100% offline operation
///
/// ## Streaming Generation
///
/// ```dart
/// final cancelToken = CancelToken();
/// final stream = edgeVeda.generateStream(
///   'Tell me a story',
///   cancelToken: cancelToken,
/// );
///
/// await for (final chunk in stream) {
///   stdout.write(chunk.token);
///   if (chunk.isFinal) break;
/// }
///
/// // To cancel mid-stream:
/// cancelToken.cancel();
/// ```
///
/// ## Model Management
///
/// ```dart
/// final modelManager = ModelManager();
///
/// // Download a pre-configured model
/// final modelPath = await modelManager.downloadModel(
///   ModelRegistry.llama32_1b,
/// );
///
/// // Monitor download progress
/// modelManager.downloadProgress.listen((progress) {
///   print('Progress: ${progress.progressPercent}%');
/// });
///
/// // Check downloaded models
/// final models = await modelManager.getDownloadedModels();
/// print('Downloaded: $models');
/// ```
///
/// ## Memory Monitoring
///
/// ```dart
/// // Check memory usage
/// final stats = await edgeVeda.getMemoryStats();
/// print('Memory: ${(stats.usagePercent * 100).toStringAsFixed(1)}%');
///
/// // Quick pressure check
/// if (await edgeVeda.isMemoryPressure()) {
///   print('High memory usage!');
/// }
/// ```
library edge_veda;

// Core SDK
export 'src/edge_veda_impl.dart' show EdgeVeda;

// Configuration and options
export 'src/types.dart' show
    EdgeVedaConfig,
    GenerateOptions,
    GenerateResponse,
    TokenChunk,
    DownloadProgress,
    ModelInfo,
    MemoryStats,
    MemoryPressureEvent,
    CancelToken;

// Exceptions (all typed, per R4.1)
export 'src/types.dart' show
    EdgeVedaException,
    EdgeVedaGenericException,
    InitializationException,
    ModelLoadException,
    GenerationException,
    DownloadException,
    ChecksumException,
    ModelValidationException,
    MemoryException,
    ConfigurationException;

// Model management
export 'src/model_manager.dart' show ModelManager, ModelRegistry;
