/**
 * Edge Veda SDK for React Native
 * On-device LLM inference with TurboModule support
 *
 * @packageDocumentation
 */

import EdgeVeda from './EdgeVeda';

// Export main SDK instance
export default EdgeVeda;

// Export types
export type {
  EdgeVedaConfig,
  GenerateOptions,
  MemoryUsage,
  MemoryStats,
  ModelInfo,
  TokenCallback,
  ProgressCallback,
  EmbeddingResult,
  GenerateResponse,
  TokenChunk,
  CancelToken,
  WhisperConfig,
  WhisperParams,
  WhisperResult,
  WhisperSegment,
  ImageGenerationConfig,
  ImageProgress,
  ImageResult,
} from './types';

export { EdgeVedaError, EdgeVedaErrorCode, GenerationError, QoSLevel, ImageSampler, ImageSchedule } from './types';

// Export ChatSession and related types
export { ChatSession } from './ChatSession';
export type { ChatMessage } from './ChatTypes';
export { ChatRole, SystemPromptPreset } from './ChatTypes';
export { ChatTemplate } from './ChatTemplate';

// Export VisionWorker and related types
export { VisionWorker } from './VisionWorker';
export { FrameQueue } from './FrameQueue';
export type {
  VisionConfig,
  VisionResult,
  VisionTimings,
  VisionGenerationParams,
  FrameData,
} from './types';

// Export WhisperSession
export { WhisperSession } from './WhisperSession';

// Export RAG pipeline
export { VectorIndex, SearchResult } from './VectorIndex';
export { RagPipeline } from './RagPipeline';
export type { RagConfig, IEdgeVeda } from './RagPipeline';

// Export ModelAdvisor
export { detectDeviceCapabilities, estimateModelMemory, recommendModels } from './ModelAdvisor';
export type { DeviceProfile } from './ModelAdvisor';

// Export Tool calling
export { ToolRegistry, ToolDefinition, ToolCall, ToolResult, ToolPriority, ToolCallParseException } from './ToolRegistry';
export { ToolTemplate, ToolTemplateFormat } from './ToolTemplate';
export { GbnfBuilder } from './GbnfBuilder';
export { SchemaValidator, SchemaValidationResult } from './SchemaValidator';

// Export native module spec (for advanced users)
export { default as NativeEdgeVeda } from './NativeEdgeVeda';
export type { Spec as NativeEdgeVedaSpec } from './NativeEdgeVeda';

// =============================================================================
// Phase 4: Runtime Supervision
// =============================================================================

// Budget types and utilities
export { Budget } from './Budget';
export type { EdgeVedaBudget, MeasuredBaseline, BudgetViolation } from './Budget';
export { BudgetProfile, BudgetConstraint, WorkloadPriority, WorkloadId } from './Budget';

// LatencyTracker
export { LatencyTracker } from './LatencyTracker';

// ResourceMonitor
export { ResourceMonitor } from './ResourceMonitor';

// ThermalMonitor
export { ThermalMonitor } from './ThermalMonitor';

// BatteryDrainTracker
export { BatteryDrainTracker } from './BatteryDrainTracker';

// Scheduler
export { Scheduler } from './Scheduler';
export type { TaskHandle, QueueStatus } from './Scheduler';
export { TaskPriority, TaskStatus } from './Scheduler';

// RuntimePolicy
export { RuntimePolicyPresets, RuntimePolicyEnforcer, detectCapabilities, throttleRecommendationToString } from './RuntimePolicy';
export type { RuntimePolicy, RuntimePolicyOptions, RuntimeCapabilities, ThrottleRecommendation, RuntimePolicyEnforcerOptions } from './RuntimePolicy';

// Telemetry
export { Telemetry, latencyStatsToString } from './Telemetry';
export type { LatencyMetric, BudgetViolationRecord, ResourceSnapshot, LatencyStats } from './Telemetry';
export { BudgetViolationType, ViolationSeverity } from './Telemetry';

// PerfTrace
export { PerfTrace } from './PerfTrace';
export type { TraceRecord } from './PerfTrace';
