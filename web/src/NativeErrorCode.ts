/**
 * NativeErrorCode — Maps C core / WASM ev_error_* integer codes to EdgeVedaError instances.
 *
 * When using the WASM backend, the compiled C core returns integer error codes
 * from its exported functions. This module provides a TypeScript enum mirroring
 * those codes and conversion utilities that translate them into typed
 * EdgeVedaError instances with appropriate EdgeVedaErrorCode values.
 *
 * Integer mapping (from core/include/edge_veda.h):
 *   0 = OK, 1 = MODEL_NOT_FOUND, 2 = MODEL_LOAD_FAILED, 3 = OUT_OF_MEMORY,
 *   4 = CONTEXT_OVERFLOW, 5 = INVALID_PARAMETER, 6 = GENERATION_FAILED,
 *   7 = CANCELLED, -1 = UNKNOWN
 */

import { EdgeVedaError, EdgeVedaErrorCode } from './types';

/**
 * Native C core / WASM error codes returned by ev_* functions.
 */
export enum NativeErrorCode {
  /** Operation completed successfully */
  OK = 0,
  /** Model file not found at specified path or URL */
  MODEL_NOT_FOUND = 1,
  /** Model failed to load (corrupt, unsupported format, etc.) */
  MODEL_LOAD_FAILED = 2,
  /** Insufficient memory (WASM heap or system) to complete operation */
  OUT_OF_MEMORY = 3,
  /** Context window capacity exceeded */
  CONTEXT_OVERFLOW = 4,
  /** Invalid parameter passed to native/WASM function */
  INVALID_PARAMETER = 5,
  /** Token generation failed */
  GENERATION_FAILED = 6,
  /** Operation was cancelled by user */
  CANCELLED = 7,
  /** Unknown or unmapped error */
  UNKNOWN = -1,
}

/** Reverse lookup map for O(1) code-to-enum conversion */
const CODE_MAP = new Map<number, NativeErrorCode>(
  Object.values(NativeErrorCode)
    .filter((v): v is number => typeof v === 'number')
    .map((code) => [code, code as NativeErrorCode])
);

/**
 * Convert a raw integer error code from the WASM module into a NativeErrorCode enum value.
 *
 * @param code - Integer error code from WASM exports
 * @returns The corresponding NativeErrorCode, or UNKNOWN for unmapped codes
 */
export function nativeErrorCodeFromInt(code: number): NativeErrorCode {
  return CODE_MAP.get(code) ?? NativeErrorCode.UNKNOWN;
}

/**
 * Convert a NativeErrorCode into a typed EdgeVedaError.
 *
 * Returns `null` for NativeErrorCode.OK (no error).
 *
 * @param code - The native error code
 * @param context - Optional context string describing what operation failed
 * @returns An EdgeVedaError instance, or null if code is OK
 */
export function nativeErrorToEdgeVedaError(
  code: NativeErrorCode,
  context?: string
): EdgeVedaError | null {
  const ctx = context ? `: ${context}` : '';

  switch (code) {
    case NativeErrorCode.OK:
      return null;

    case NativeErrorCode.MODEL_NOT_FOUND:
      return new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_FOUND,
        `Model not found${ctx}`,
        'Verify the model URL is accessible or the model is cached in IndexedDB.'
      );

    case NativeErrorCode.MODEL_LOAD_FAILED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        `Model failed to load${ctx}`,
        'The model file may be corrupt or in an unsupported format.'
      );

    case NativeErrorCode.OUT_OF_MEMORY:
      return new EdgeVedaError(
        EdgeVedaErrorCode.OUT_OF_MEMORY,
        `Out of memory${ctx}`,
        'The WASM heap or browser memory limit was exceeded. Try a smaller model or reduce context size.'
      );

    case NativeErrorCode.CONTEXT_OVERFLOW:
      return new EdgeVedaError(
        EdgeVedaErrorCode.CONTEXT_OVERFLOW,
        `Context overflow${ctx}`,
        'The input exceeds the model context window. Reset context or reduce input length.'
      );

    case NativeErrorCode.INVALID_PARAMETER:
      return new EdgeVedaError(
        EdgeVedaErrorCode.INVALID_CONFIG,
        `Invalid parameter${ctx}`,
        'Check that all configuration values are within valid ranges.'
      );

    case NativeErrorCode.GENERATION_FAILED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        `Generation failed${ctx}`,
        'Token generation encountered an error. Try resetting context.'
      );

    case NativeErrorCode.CANCELLED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.CANCELLATION,
        `Operation cancelled${ctx}`
      );

    case NativeErrorCode.UNKNOWN:
    default:
      return new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        `Unknown native error (code: ${code})${ctx}`,
        'An unexpected error occurred in the WASM layer.'
      );
  }
}

/**
 * Check a native error code and throw if it represents an error.
 *
 * Convenience method for call sites that want to throw-on-error
 * rather than inspect a nullable return value.
 *
 * @param code - The native error code to check (enum or raw integer)
 * @param context - Optional context string for the error message
 * @throws EdgeVedaError if code is not OK
 */
export function throwIfNativeError(
  code: NativeErrorCode | number,
  context?: string
): void {
  const nativeCode =
    typeof code === 'number' ? nativeErrorCodeFromInt(code) : code;
  const error = nativeErrorToEdgeVedaError(nativeCode, context);
  if (error) {
    throw error;
  }
}