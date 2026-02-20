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
  ModelInfo,
  TokenCallback,
  ProgressCallback,
} from './types';

export { EdgeVedaError, EdgeVedaErrorCode } from './types';

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
