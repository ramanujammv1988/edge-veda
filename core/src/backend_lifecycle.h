#pragma once

#ifdef EDGE_VEDA_LLAMA_ENABLED

// Acquire shared llama backend resources. Safe to call multiple times.
void edge_veda_backend_acquire();

// Release shared llama backend resources. Frees backend when last user exits.
void edge_veda_backend_release();

#endif  // EDGE_VEDA_LLAMA_ENABLED
