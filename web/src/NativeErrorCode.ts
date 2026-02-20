/**
 * NativeErrorCode — Maps C core / WASM ev_error_t integer codes to EdgeVedaError instances.
 *
 * When using the WASM backend, the compiled C core returns integer error codes
 * from its exported functions. This module provides a TypeScript enum mirroring
 * those codes and conversion utilities that translate them into typed
 * EdgeVedaError instances with appropriate EdgeVedaErrorCode values.
 *
 * Integer mapping (from core/include/edge_veda.h — ev_error_t):
 *   0 = OK, -1 = INVALID_PARAMETER, -2 = OUT_OF_MEMORY, -3 = MODEL_LOAD_FAILED,
 *   -4 = BACKEND_INIT_FAILED, -5 = INFERENCE_FAILED, -6 = CONTEXT_INVALID,
 *   -7 = STREAM_ENDED, -8 = NOT_IMPLEMENTED, -9 = MEMORY_LIMIT_EXCEEDED,
 *   -10 = UNSUPPORTED_BACKEND, -999 = UNKNOWN
 */

import { EdgeVedaError, EdgeVedaErrorCode } from './types';

/**
 * Native C core / WASM error codes returned by ev_* functions.
 */
export enum NativeErrorCode {
  /** Operation completed successfully */
  OK = 0,
  /** Invalid parameter passed to native/WASM function */
  INVALID_PARAMETER = -1,
  /** Insufficient memory (WASM heap or system) to complete operation */
  OUT_OF_MEMORY = -2,
  /** Model failed to load (corrupt, unsupported format, etc.) */
  MODEL_LOAD_FAILED = -3,
  /** Backend (WebGPU/WASM) failed to initialise */
  BACKEND_INIT_FAILED = -4,
  /** Token inference failed */
  INFERENCE_FAILED = -5,
  /** KV context is in an invalid state */
  CONTEXT_INVALID = -6,
  /** Streaming ended (not an error — signals end of token stream) */
  STREAM_ENDED = -7,
  /** Feature not implemented in this build */
  NOT_IMPLEMENTED = -8,
  /** Memory limit exceeded */
  MEMORY_LIMIT_EXCEEDED = -9,
  /** Requested backend is not supported on this platform */
  UNSUPPORTED_BACKEND = -10,
  /** Unknown or unmapped error */
  UNKNOWN = -999,
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

    case NativeErrorCode.INVALID_PARAMETER:
      return new EdgeVedaError(
        EdgeVedaErrorCode.INVALID_CONFIG,
        `Invalid parameter${ctx}`,
        'Check that all configuration values are within valid ranges.'
      );

    case NativeErrorCode.OUT_OF_MEMORY:
      return new EdgeVedaError(
        EdgeVedaErrorCode.OUT_OF_MEMORY,
        `Out of memory${ctx}`,
        'The WASM heap or browser memory limit was exceeded. Try a smaller model or reduce context size.'
      );

    case NativeErrorCode.MODEL_LOAD_FAILED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_LOAD_FAILED,
        `Model failed to load${ctx}`,
        'The model file may be corrupt or in an unsupported format.'
      );

    case NativeErrorCode.BACKEND_INIT_FAILED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        `Backend initialisation failed${ctx}`,
        'WebGPU or WASM backend could not be initialised. Try falling back to a different device.'
      );

    case NativeErrorCode.INFERENCE_FAILED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.GENERATION_FAILED,
        `Inference failed${ctx}`,
        'Token generation encountered an error. Try resetting context.'
      );

    case NativeErrorCode.CONTEXT_INVALID:
      return new EdgeVedaError(
        EdgeVedaErrorCode.CONTEXT_OVERFLOW,
        `Context invalid${ctx}`,
        'The KV context is in an invalid state. Reset context before retrying.'
      );

    case NativeErrorCode.STREAM_ENDED:
      // Not an error — signals natural end of token stream
      return null;

    case NativeErrorCode.NOT_IMPLEMENTED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        `Feature not implemented${ctx}`,
        'This feature is not available in the current WASM build.'
      );

    case NativeErrorCode.MEMORY_LIMIT_EXCEEDED:
      return new EdgeVedaError(
        EdgeVedaErrorCode.OUT_OF_MEMORY,
        `Memory limit exceeded${ctx}`,
        'The model exceeds available WASM heap. Try a smaller model or reduce context size.'
      );

    case NativeErrorCode.UNSUPPORTED_BACKEND:
      return new EdgeVedaError(
        EdgeVedaErrorCode.UNKNOWN_ERROR,
        `Unsupported backend${ctx}`,
        'The requested backend (WebGPU/WASM) is not supported on this platform.'
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