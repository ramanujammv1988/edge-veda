// Pre-JS for Edge Veda WASM module
// This runs before the Emscripten module initializes

if (typeof Module === 'undefined') Module = {};

Module['onRuntimeInitialized'] = function() {
  if (typeof postMessage === 'function') {
    postMessage({ type: 'wasm_ready' });
  }
};
