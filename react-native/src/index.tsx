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

// Export native module spec (for advanced users)
export { default as NativeEdgeVeda } from './NativeEdgeVeda';
export type { Spec as NativeEdgeVedaSpec } from './NativeEdgeVeda';
