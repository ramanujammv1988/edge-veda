/**
 * Edge Veda Web Worker — runs WASM inference off the main thread.
 *
 * Protocol:
 *   Main → Worker:  { type, id, payload }
 *   Worker → Main:  { type, id, payload?, error? }
 *
 * Types: init, generate, stream_start, stream_next, stream_cancel, embed, memory, dispose
 */

let Module = null;
let context = null;
let activeStream = null;

// Wrapped C functions (populated after init)
let ev_init, ev_free, ev_generate, ev_free_string;
let ev_generate_stream, ev_stream_next, ev_stream_free, ev_stream_cancel;
let ev_config_default, ev_generation_params_default;
let ev_get_memory_usage, ev_embed, ev_free_embeddings, ev_version;

importScripts('wasm/edge_veda.js');

self.onmessage = async function(e) {
  const { type, id, payload } = e.data;

  try {
    switch (type) {
      case 'init': {
        Module = await EdgeVedaWasm();

        // Wrap C functions
        ev_init = Module.cwrap('ev_init', 'number', ['number', 'number']);
        ev_free = Module.cwrap('ev_free', null, ['number']);
        ev_generate = Module.cwrap('ev_generate', 'number', ['number', 'string', 'number', 'number']);
        ev_free_string = Module.cwrap('ev_free_string', null, ['number']);
        ev_generate_stream = Module.cwrap('ev_generate_stream', 'number', ['number', 'string', 'number', 'number']);
        ev_stream_next = Module.cwrap('ev_stream_next', 'number', ['number', 'number']);
        ev_stream_free = Module.cwrap('ev_stream_free', null, ['number']);
        ev_stream_cancel = Module.cwrap('ev_stream_cancel', null, ['number']);
        ev_version = Module.cwrap('ev_version', 'string', []);
        ev_config_default = Module.cwrap('ev_config_default', null, ['number']);
        ev_generation_params_default = Module.cwrap('ev_generation_params_default', null, ['number']);
        ev_get_memory_usage = Module.cwrap('ev_get_memory_usage', 'number', ['number', 'number']);
        ev_embed = Module.cwrap('ev_embed', 'number', ['number', 'string', 'number']);
        ev_free_embeddings = Module.cwrap('ev_free_embeddings', null, ['number']);

        // Allocate and fill config struct
        const configSize = 128; // Generous size for ev_config
        const configPtr = Module._malloc(configSize);
        ev_config_default(configPtr);

        // Write model path
        const modelPathPtr = Module.allocateUTF8(payload.modelPath);
        Module.HEAPU32[configPtr >> 2] = modelPathPtr;

        // Set fields
        if (payload.numThreads) Module.HEAP32[(configPtr + 12) >> 2] = payload.numThreads;
        if (payload.contextSize) Module.HEAP32[(configPtr + 16) >> 2] = payload.contextSize;

        const errorPtr = Module._malloc(4);
        context = ev_init(configPtr, errorPtr);
        const error = Module.HEAP32[errorPtr >> 2];

        Module._free(errorPtr);
        Module._free(configPtr);
        Module._free(modelPathPtr);

        if (!context || error !== 0) {
          throw new Error('Failed to initialize: error code ' + error);
        }

        self.postMessage({ type: 'init_done', id, payload: { version: ev_version() } });
        break;
      }

      case 'generate': {
        if (!context) throw new Error('Not initialized');

        const paramsSize = 128;
        const paramsPtr = Module._malloc(paramsSize);
        ev_generation_params_default(paramsPtr);

        if (payload.maxTokens) Module.HEAP32[paramsPtr >> 2] = payload.maxTokens;

        const outputPtrPtr = Module._malloc(4);
        const error = ev_generate(context, payload.prompt, paramsPtr, outputPtrPtr);

        if (error !== 0) {
          Module._free(paramsPtr);
          Module._free(outputPtrPtr);
          throw new Error('Generation failed: ' + error);
        }

        const outputPtr = Module.HEAPU32[outputPtrPtr >> 2];
        const text = Module.UTF8ToString(outputPtr);
        ev_free_string(outputPtr);
        Module._free(paramsPtr);
        Module._free(outputPtrPtr);

        self.postMessage({ type: 'generate_done', id, payload: { text } });
        break;
      }

      case 'stream_start': {
        if (!context) throw new Error('Not initialized');

        const paramsSize = 128;
        const paramsPtr = Module._malloc(paramsSize);
        ev_generation_params_default(paramsPtr);
        if (payload.maxTokens) Module.HEAP32[paramsPtr >> 2] = payload.maxTokens;

        const errorPtr = Module._malloc(4);
        activeStream = ev_generate_stream(context, payload.prompt, paramsPtr, errorPtr);
        const error = Module.HEAP32[errorPtr >> 2];
        Module._free(paramsPtr);
        Module._free(errorPtr);

        if (!activeStream || error !== 0) {
          throw new Error('Stream start failed: ' + error);
        }

        self.postMessage({ type: 'stream_started', id });
        break;
      }

      case 'stream_next': {
        if (!activeStream) {
          self.postMessage({ type: 'stream_end', id });
          break;
        }

        const errorPtr = Module._malloc(4);
        const tokenPtr = ev_stream_next(activeStream, errorPtr);
        Module._free(errorPtr);

        if (!tokenPtr) {
          ev_stream_free(activeStream);
          activeStream = null;
          self.postMessage({ type: 'stream_end', id });
        } else {
          const token = Module.UTF8ToString(tokenPtr);
          ev_free_string(tokenPtr);
          self.postMessage({ type: 'stream_token', id, payload: { token } });
        }
        break;
      }

      case 'stream_cancel': {
        if (activeStream) {
          ev_stream_cancel(activeStream);
          ev_stream_free(activeStream);
          activeStream = null;
        }
        self.postMessage({ type: 'stream_cancelled', id });
        break;
      }

      case 'dispose': {
        if (activeStream) {
          ev_stream_cancel(activeStream);
          ev_stream_free(activeStream);
          activeStream = null;
        }
        if (context) {
          ev_free(context);
          context = null;
        }
        self.postMessage({ type: 'disposed', id });
        break;
      }

      default:
        throw new Error('Unknown message type: ' + type);
    }
  } catch (err) {
    self.postMessage({ type: 'error', id, error: err.message || String(err) });
  }
};
