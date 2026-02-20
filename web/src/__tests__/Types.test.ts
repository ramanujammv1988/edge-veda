import {
  EdgeVedaError,
  EdgeVedaErrorCode,
  InitializationError,
  ModelLoadError,
  GenerationError,
  MemoryError,
  ConfigurationException,
  CancelToken,
} from '../types';

describe('EdgeVedaErrorCode enum', () => {
  it('has MODEL_NOT_FOUND', () => {
    expect(EdgeVedaErrorCode.MODEL_NOT_FOUND).toBe('MODEL_NOT_FOUND');
  });

  it('has MODEL_LOAD_FAILED', () => {
    expect(EdgeVedaErrorCode.MODEL_LOAD_FAILED).toBe('MODEL_LOAD_FAILED');
  });

  it('has GENERATION_FAILED', () => {
    expect(EdgeVedaErrorCode.GENERATION_FAILED).toBe('GENERATION_FAILED');
  });

  it('has OUT_OF_MEMORY', () => {
    expect(EdgeVedaErrorCode.OUT_OF_MEMORY).toBe('OUT_OF_MEMORY');
  });

  it('has CONTEXT_OVERFLOW', () => {
    expect(EdgeVedaErrorCode.CONTEXT_OVERFLOW).toBe('CONTEXT_OVERFLOW');
  });

  it('has INVALID_CONFIG', () => {
    expect(EdgeVedaErrorCode.INVALID_CONFIG).toBe('INVALID_CONFIG');
  });

  it('has CANCELLATION', () => {
    expect(EdgeVedaErrorCode.CANCELLATION).toBe('CANCELLATION');
  });

  it('has VISION_ERROR', () => {
    expect(EdgeVedaErrorCode.VISION_ERROR).toBe('VISION_ERROR');
  });

  it('has UNLOAD_ERROR', () => {
    expect(EdgeVedaErrorCode.UNLOAD_ERROR).toBe('UNLOAD_ERROR');
  });

  it('has UNKNOWN_ERROR', () => {
    expect(EdgeVedaErrorCode.UNKNOWN_ERROR).toBe('UNKNOWN_ERROR');
  });

  it('has exactly 10 values', () => {
    const values = Object.values(EdgeVedaErrorCode);
    expect(values).toHaveLength(10);
  });
});

describe('EdgeVedaError', () => {
  it('is instanceof Error', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.UNKNOWN_ERROR, 'test');
    expect(err).toBeInstanceOf(Error);
  });

  it('is instanceof EdgeVedaError', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.UNKNOWN_ERROR, 'test');
    expect(err).toBeInstanceOf(EdgeVedaError);
  });

  it('stores code property', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.MODEL_NOT_FOUND, 'not found');
    expect(err.code).toBe(EdgeVedaErrorCode.MODEL_NOT_FOUND);
  });

  it('name === "EdgeVedaError"', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.UNKNOWN_ERROR, 'msg');
    expect(err.name).toBe('EdgeVedaError');
  });

  it('message is set correctly', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.GENERATION_FAILED, 'gen failed');
    expect(err.message).toBe('gen failed');
  });

  it('stores optional details', () => {
    const err = new EdgeVedaError(
      EdgeVedaErrorCode.UNKNOWN_ERROR,
      'msg',
      'extra detail'
    );
    expect(err.details).toBe('extra detail');
  });

  it('details is undefined when not provided', () => {
    const err = new EdgeVedaError(EdgeVedaErrorCode.UNKNOWN_ERROR, 'msg');
    expect(err.details).toBeUndefined();
  });
});

describe('InitializationError', () => {
  it('is instanceof Error', () => {
    expect(new InitializationError('init failed')).toBeInstanceOf(Error);
  });

  it('is instanceof EdgeVedaError', () => {
    expect(new InitializationError('init failed')).toBeInstanceOf(EdgeVedaError);
  });

  it('is instanceof InitializationError', () => {
    expect(new InitializationError('init failed')).toBeInstanceOf(InitializationError);
  });

  it('name === "InitializationError"', () => {
    const err = new InitializationError('init failed');
    expect(err.name).toBe('InitializationError');
  });

  it('message is preserved', () => {
    const err = new InitializationError('backend init failed');
    expect(err.message).toBe('backend init failed');
  });

  it('code is UNKNOWN_ERROR', () => {
    const err = new InitializationError('msg');
    expect(err.code).toBe(EdgeVedaErrorCode.UNKNOWN_ERROR);
  });
});

describe('ModelLoadError', () => {
  it('is instanceof EdgeVedaError', () => {
    expect(new ModelLoadError('load failed')).toBeInstanceOf(EdgeVedaError);
  });

  it('name === "ModelLoadError"', () => {
    const err = new ModelLoadError('bad gguf');
    expect(err.name).toBe('ModelLoadError');
  });

  it('code is MODEL_LOAD_FAILED', () => {
    const err = new ModelLoadError('msg');
    expect(err.code).toBe(EdgeVedaErrorCode.MODEL_LOAD_FAILED);
  });

  it('stores optional details', () => {
    const err = new ModelLoadError('msg', 'corrupt file');
    expect(err.details).toBe('corrupt file');
  });
});

describe('GenerationError', () => {
  it('is instanceof EdgeVedaError', () => {
    expect(new GenerationError('gen failed')).toBeInstanceOf(EdgeVedaError);
  });

  it('name === "GenerationError"', () => {
    const err = new GenerationError('inference failed');
    expect(err.name).toBe('GenerationError');
  });

  it('code is GENERATION_FAILED', () => {
    const err = new GenerationError('msg');
    expect(err.code).toBe(EdgeVedaErrorCode.GENERATION_FAILED);
  });
});

describe('MemoryError', () => {
  it('is instanceof EdgeVedaError', () => {
    expect(new MemoryError('oom')).toBeInstanceOf(EdgeVedaError);
  });

  it('name === "MemoryError"', () => {
    const err = new MemoryError('out of memory');
    expect(err.name).toBe('MemoryError');
  });

  it('code is OUT_OF_MEMORY', () => {
    const err = new MemoryError('msg');
    expect(err.code).toBe(EdgeVedaErrorCode.OUT_OF_MEMORY);
  });
});

describe('ConfigurationException', () => {
  it('is instanceof Error', () => {
    expect(new ConfigurationException('bad config')).toBeInstanceOf(Error);
  });

  it('is NOT instanceof EdgeVedaError', () => {
    expect(new ConfigurationException('bad config')).not.toBeInstanceOf(
      EdgeVedaError
    );
  });

  it('name === "ConfigurationException"', () => {
    const err = new ConfigurationException('invalid tool');
    expect(err.name).toBe('ConfigurationException');
  });

  it('message is preserved', () => {
    const err = new ConfigurationException('bad param');
    expect(err.message).toBe('bad param');
  });

  it('stores optional details', () => {
    const err = new ConfigurationException('bad', 'field: foo');
    expect(err.details).toBe('field: foo');
  });

  it('details is undefined when not provided', () => {
    const err = new ConfigurationException('bad');
    expect(err.details).toBeUndefined();
  });
});

describe('CancelToken', () => {
  it('starts as not cancelled', () => {
    const token = new CancelToken();
    expect(token.cancelled).toBe(false);
  });

  it('cancelled becomes true after cancel()', () => {
    const token = new CancelToken();
    token.cancel();
    expect(token.cancelled).toBe(true);
  });

  it('onCancel callback fires on cancel()', () => {
    const token = new CancelToken();
    const cb = jest.fn();
    token.onCancel(cb);
    expect(cb).not.toHaveBeenCalled();
    token.cancel();
    expect(cb).toHaveBeenCalledTimes(1);
  });

  it('onCancel callback fires immediately if already cancelled', () => {
    const token = new CancelToken();
    token.cancel();
    const cb = jest.fn();
    token.onCancel(cb);
    expect(cb).toHaveBeenCalledTimes(1);
  });

  it('cancel() is idempotent — callback not called twice', () => {
    const token = new CancelToken();
    const cb = jest.fn();
    token.onCancel(cb);
    token.cancel();
    token.cancel();
    expect(cb).toHaveBeenCalledTimes(1);
  });

  it('throwIfCancelled does not throw before cancel', () => {
    const token = new CancelToken();
    expect(() => token.throwIfCancelled()).not.toThrow();
  });

  it('throwIfCancelled throws EdgeVedaError after cancel', () => {
    const token = new CancelToken();
    token.cancel();
    expect(() => token.throwIfCancelled()).toThrow(EdgeVedaError);
  });

  it('throwIfCancelled throws error with CANCELLATION code', () => {
    const token = new CancelToken();
    token.cancel();
    try {
      token.throwIfCancelled();
      fail('Expected to throw');
    } catch (err) {
      expect(err).toBeInstanceOf(EdgeVedaError);
      expect((err as EdgeVedaError).code).toBe(EdgeVedaErrorCode.CANCELLATION);
    }
  });

  it('signal is an AbortSignal', () => {
    const token = new CancelToken();
    expect(token.signal).toBeInstanceOf(AbortSignal);
  });

  it('signal.aborted is true after cancel()', () => {
    const token = new CancelToken();
    token.cancel();
    expect(token.signal.aborted).toBe(true);
  });
});
