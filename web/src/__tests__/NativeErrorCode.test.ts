import {
  NativeErrorCode,
  nativeErrorCodeFromInt,
  nativeErrorToEdgeVedaError,
  throwIfNativeError,
} from '../NativeErrorCode';
import { EdgeVedaError } from '../types';

describe('NativeErrorCode', () => {
  describe('enum values', () => {
    it('OK === 0', () => {
      expect(NativeErrorCode.OK).toBe(0);
    });

    it('INVALID_PARAMETER === -1', () => {
      expect(NativeErrorCode.INVALID_PARAMETER).toBe(-1);
    });

    it('OUT_OF_MEMORY === -2', () => {
      expect(NativeErrorCode.OUT_OF_MEMORY).toBe(-2);
    });

    it('MODEL_LOAD_FAILED === -3', () => {
      expect(NativeErrorCode.MODEL_LOAD_FAILED).toBe(-3);
    });

    it('BACKEND_INIT_FAILED === -4', () => {
      expect(NativeErrorCode.BACKEND_INIT_FAILED).toBe(-4);
    });

    it('INFERENCE_FAILED === -5', () => {
      expect(NativeErrorCode.INFERENCE_FAILED).toBe(-5);
    });

    it('CONTEXT_INVALID === -6', () => {
      expect(NativeErrorCode.CONTEXT_INVALID).toBe(-6);
    });

    it('STREAM_ENDED === -7', () => {
      expect(NativeErrorCode.STREAM_ENDED).toBe(-7);
    });

    it('NOT_IMPLEMENTED === -8', () => {
      expect(NativeErrorCode.NOT_IMPLEMENTED).toBe(-8);
    });

    it('MEMORY_LIMIT_EXCEEDED === -9', () => {
      expect(NativeErrorCode.MEMORY_LIMIT_EXCEEDED).toBe(-9);
    });

    it('UNSUPPORTED_BACKEND === -10', () => {
      expect(NativeErrorCode.UNSUPPORTED_BACKEND).toBe(-10);
    });

    it('UNKNOWN === -999', () => {
      expect(NativeErrorCode.UNKNOWN).toBe(-999);
    });
  });

  describe('nativeErrorCodeFromInt', () => {
    it.each([
      [0, NativeErrorCode.OK],
      [-1, NativeErrorCode.INVALID_PARAMETER],
      [-2, NativeErrorCode.OUT_OF_MEMORY],
      [-3, NativeErrorCode.MODEL_LOAD_FAILED],
      [-4, NativeErrorCode.BACKEND_INIT_FAILED],
      [-5, NativeErrorCode.INFERENCE_FAILED],
      [-6, NativeErrorCode.CONTEXT_INVALID],
      [-7, NativeErrorCode.STREAM_ENDED],
      [-8, NativeErrorCode.NOT_IMPLEMENTED],
      [-9, NativeErrorCode.MEMORY_LIMIT_EXCEEDED],
      [-10, NativeErrorCode.UNSUPPORTED_BACKEND],
      [-999, NativeErrorCode.UNKNOWN],
    ])('maps %i → NativeErrorCode %i', (code, expected) => {
      expect(nativeErrorCodeFromInt(code)).toBe(expected);
    });

    it('maps unmapped integer to UNKNOWN', () => {
      expect(nativeErrorCodeFromInt(-42)).toBe(NativeErrorCode.UNKNOWN);
    });

    it('maps positive unmapped integer to UNKNOWN', () => {
      expect(nativeErrorCodeFromInt(99)).toBe(NativeErrorCode.UNKNOWN);
    });
  });

  describe('nativeErrorToEdgeVedaError', () => {
    it('returns null for OK', () => {
      expect(nativeErrorToEdgeVedaError(NativeErrorCode.OK)).toBeNull();
    });

    it('returns null for STREAM_ENDED (sentinel, not an error)', () => {
      expect(nativeErrorToEdgeVedaError(NativeErrorCode.STREAM_ENDED)).toBeNull();
    });

    it('returns EdgeVedaError for INVALID_PARAMETER', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.INVALID_PARAMETER);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for OUT_OF_MEMORY', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.OUT_OF_MEMORY);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for MODEL_LOAD_FAILED', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.MODEL_LOAD_FAILED);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for BACKEND_INIT_FAILED', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.BACKEND_INIT_FAILED);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for INFERENCE_FAILED', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.INFERENCE_FAILED);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for CONTEXT_INVALID', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.CONTEXT_INVALID);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for NOT_IMPLEMENTED', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.NOT_IMPLEMENTED);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for MEMORY_LIMIT_EXCEEDED', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.MEMORY_LIMIT_EXCEEDED);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for UNSUPPORTED_BACKEND', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.UNSUPPORTED_BACKEND);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('returns EdgeVedaError for UNKNOWN', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.UNKNOWN);
      expect(err).toBeInstanceOf(EdgeVedaError);
    });

    it('includes context string in error message when provided', () => {
      const err = nativeErrorToEdgeVedaError(
        NativeErrorCode.INFERENCE_FAILED,
        'token decode'
      );
      expect(err).not.toBeNull();
      expect(err!.message).toContain('token decode');
    });

    it('error message excludes context suffix when context is omitted', () => {
      const err = nativeErrorToEdgeVedaError(NativeErrorCode.INFERENCE_FAILED);
      expect(err).not.toBeNull();
      // Should not have the ": " separator without context
      expect(err!.message).not.toMatch(/:\s*$/);
    });
  });

  describe('throwIfNativeError', () => {
    it('does not throw for OK', () => {
      expect(() => throwIfNativeError(NativeErrorCode.OK)).not.toThrow();
    });

    it('does not throw for STREAM_ENDED', () => {
      expect(() => throwIfNativeError(NativeErrorCode.STREAM_ENDED)).not.toThrow();
    });

    it('throws EdgeVedaError for INFERENCE_FAILED', () => {
      expect(() => throwIfNativeError(NativeErrorCode.INFERENCE_FAILED)).toThrow(
        EdgeVedaError
      );
    });

    it('throws EdgeVedaError for MODEL_LOAD_FAILED', () => {
      expect(() => throwIfNativeError(NativeErrorCode.MODEL_LOAD_FAILED)).toThrow(
        EdgeVedaError
      );
    });

    it('accepts a raw integer and throws for error codes', () => {
      expect(() => throwIfNativeError(-5)).toThrow(EdgeVedaError);
    });

    it('accepts raw integer 0 (OK) without throwing', () => {
      expect(() => throwIfNativeError(0)).not.toThrow();
    });

    it('accepts raw integer -7 (STREAM_ENDED) without throwing', () => {
      expect(() => throwIfNativeError(-7)).not.toThrow();
    });
  });
});
