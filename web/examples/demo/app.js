/**
 * Edge Veda Web Demo — Application Logic
 *
 * Loads a GGUF model via WASM and generates text in-browser.
 * Uses the Edge Veda Web SDK (EdgeVeda, ChatSession, model-cache).
 */

// ======================== State ========================
/** @type {import('../../src/index').EdgeVeda | null} */
let edgeVeda = null;

/** @type {import('../../src/index').ChatSession | null} */
let chatSession = null;

let isInitialized = false;
let isStreaming = false;
let currentPreset = 'assistant';
let messages = [];

// SDK module references (populated after dynamic import)
let SDK = null;

// Default model configuration — GGUF model loaded via WASM
const MODEL_CONFIG = {
  modelId: 'llama-3.2-1b-q4_k_m',
  downloadUrl: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
  name: 'Llama 3.2 1B Instruct',
  sizeBytes: 750_000_000,
  quantization: 'Q4_K_M',
};

// ======================== Screen Navigation ========================
function showMain() {
  document.getElementById('welcome-screen').classList.remove('active');
  document.getElementById('main-screen').classList.add('active');
  checkWebGPU();
}

function switchTab(tabKey) {
  document.querySelectorAll('.tab').forEach((t) => t.classList.remove('active'));
  document.querySelectorAll('.tab-panel').forEach((p) => p.classList.remove('active'));
  document.querySelector(`.tab[data-tab="${tabKey}"]`).classList.add('active');
  document.getElementById(`tab-${tabKey}`).classList.add('active');
}

// ======================== WebGPU Check ========================
async function checkWebGPU() {
  const hasWebGPU = !!navigator.gpu;
  const webgpuStatus = document.getElementById('webgpu-status');
  const deviceMeta = document.getElementById('device-meta-text');

  if (hasWebGPU) {
    try {
      const adapter = await navigator.gpu.requestAdapter();
      if (adapter) {
        webgpuStatus.textContent = 'Available ✓';
        webgpuStatus.style.color = '#66BB6A';
        deviceMeta.textContent = 'WebAssembly • WebGPU ✓';
      } else {
        webgpuStatus.textContent = 'No adapter';
        deviceMeta.textContent = 'WebAssembly • WebGPU unavailable';
      }
    } catch {
      webgpuStatus.textContent = 'Error';
      deviceMeta.textContent = 'WebAssembly only';
    }
  } else {
    webgpuStatus.textContent = 'Not supported';
    webgpuStatus.style.color = '#EF5350';
    deviceMeta.textContent = 'WebAssembly only';
  }
}

// ======================== Engine Initialization ========================
/**
 * Initializes the Edge Veda inference engine:
 * 1. Dynamically imports the SDK
 * 2. Downloads the GGUF model to IndexedDB (with progress)
 * 3. Creates EdgeVeda instance and loads model via WASM worker
 * 4. Creates a ChatSession for multi-turn conversation
 */
async function initializeEngine() {
  const statusText = document.getElementById('status-text');
  const statusSpinner = document.getElementById('status-spinner');
  const initBtn = document.getElementById('init-btn');
  const promptInput = document.getElementById('prompt-input');
  const sendBtn = document.getElementById('send-btn');

  initBtn.classList.add('hidden');
  statusSpinner.classList.remove('hidden');
  statusText.textContent = 'Loading Edge Veda SDK...';
  statusText.className = 'status-text warning';

  try {
    // Step 1: Dynamic import of Edge Veda Web SDK
    SDK = await import('../../src/index.js');
    const EdgeVeda = SDK.default || SDK.EdgeVeda;
    const ChatSession = SDK.ChatSession;

    // Step 2: Download GGUF model with progress (cached in IndexedDB)
    statusText.textContent = 'Checking model cache...';

    const hasCached = await SDK.getCachedModel(MODEL_CONFIG.modelId);
    if (!hasCached) {
      statusText.textContent = 'Downloading GGUF model (~750 MB)...';

      // Use the SDK's downloadModelWithRetry for robust downloading
      if (SDK.downloadModelWithRetry) {
        await SDK.downloadModelWithRetry(
          {
            id: MODEL_CONFIG.modelId,
            downloadUrl: MODEL_CONFIG.downloadUrl,
            sizeBytes: MODEL_CONFIG.sizeBytes,
            name: MODEL_CONFIG.name,
          },
          {
            precision: 'q4',
            onProgress: (progress) => {
              const pct = progress.percentage || 0;
              const mb = (progress.downloadedBytes / (1024 * 1024)).toFixed(0);
              const totalMb = (progress.totalBytes / (1024 * 1024)).toFixed(0);
              const speed = progress.speedBytesPerSecond
                ? `${(progress.speedBytesPerSecond / (1024 * 1024)).toFixed(1)} MB/s`
                : '';
              const eta = progress.estimatedSecondsRemaining != null
                ? `${progress.estimatedSecondsRemaining}s remaining`
                : '';

              statusText.textContent = `Downloading: ${mb}/${totalMb} MB (${pct}%) ${speed} ${eta}`;

              // Update progress bar if visible
              const progressBar = document.getElementById('download-progress');
              if (progressBar) {
                progressBar.style.width = `${pct}%`;
              }
            },
          }
        );
      }

      statusText.textContent = 'Model downloaded and cached.';
    } else {
      statusText.textContent = 'Model found in cache.';
    }

    // Step 3: Create EdgeVeda instance and initialize with WASM
    statusText.textContent = 'Initializing WASM inference engine...';

    edgeVeda = new EdgeVeda({
      modelId: MODEL_CONFIG.modelId,
      device: 'auto', // Will use WebGPU if available, WASM fallback
      precision: 'q4',
      maxContextLength: 2048,
      enableCache: true,
      numThreads: navigator.hardwareConcurrency || 4,
      onProgress: (progress) => {
        statusText.textContent = progress.message || `${progress.stage}: ${Math.round(progress.progress)}%`;
      },
      onError: (error) => {
        console.error('[Veda] Engine error:', error);
        statusText.textContent = `Error: ${error.message}`;
        statusText.className = 'status-text warning';
      },
    });

    await edgeVeda.init();

    // Step 4: Create ChatSession for multi-turn conversation
    if (ChatSession) {
      chatSession = new ChatSession(edgeVeda, currentPreset);
    }

    isInitialized = true;

    statusText.textContent = 'Ready to chat!';
    statusText.className = 'status-text success';
    statusSpinner.classList.add('hidden');

    // Enable UI
    promptInput.disabled = false;
    sendBtn.disabled = false;
    document.getElementById('metrics-bar').classList.remove('hidden');
    document.getElementById('persona-picker').classList.remove('hidden');

    populateModelList();
  } catch (e) {
    console.error('Initialization error:', e);

    // If SDK loading/WASM init fails, fall back to demo mode
    statusText.textContent = `SDK init failed: ${e.message}. Running in demo mode.`;
    statusText.className = 'status-text warning';
    statusSpinner.classList.add('hidden');

    // Enable demo mode anyway so user can experience the UI
    isInitialized = true;
    edgeVeda = null;
    chatSession = null;
    promptInput.disabled = false;
    sendBtn.disabled = false;
    document.getElementById('metrics-bar').classList.remove('hidden');
    document.getElementById('persona-picker').classList.remove('hidden');
  }
}

// ======================== Chat ========================
/**
 * Sends a message and generates a streaming response.
 * Uses EdgeVeda.generateStream() for real WASM inference,
 * or falls back to demo mode if SDK isn't loaded.
 */
async function sendMessage() {
  const promptInput = document.getElementById('prompt-input');
  const prompt = promptInput.value.trim();
  if (!prompt || !isInitialized || isStreaming) return;

  promptInput.value = '';
  promptInput.style.height = 'auto';
  isStreaming = true;

  const sendBtn = document.getElementById('send-btn');
  sendBtn.textContent = '■';
  sendBtn.classList.add('stop');
  sendBtn.onclick = cancelGeneration;

  // Add user message
  addMessage('user', prompt);
  clearEmptyState();
  document.getElementById('persona-picker').classList.add('hidden');
  updateContextIndicator();

  const statusText = document.getElementById('status-text');
  statusText.textContent = 'Generating...';
  statusText.className = 'status-text success';

  const start = performance.now();
  let tokenCount = 0;
  let receivedFirst = false;
  let accumulated = '';

  const temperature = parseFloat(document.getElementById('temp-slider').value) || 0.7;
  const maxTokens = parseInt(document.getElementById('tokens-slider').value) || 256;

  try {
    if (edgeVeda && typeof edgeVeda.generateStream === 'function') {
      // ===== Real WASM inference path =====
      const generateOptions = {
        prompt: buildPrompt(prompt),
        maxTokens,
        temperature,
        topP: 0.9,
        topK: 40,
      };

      for await (const chunk of edgeVeda.generateStream(generateOptions)) {
        if (!isStreaming) break; // User cancelled

        if (!receivedFirst && chunk.token) {
          document.getElementById('metric-ttft').textContent = `${Math.round(performance.now() - start)}ms`;
          receivedFirst = true;
        }

        if (chunk.token) {
          accumulated += chunk.token;
          tokenCount++;
          updateStreamingBubble(accumulated);

          if (tokenCount % 5 === 0) {
            statusText.textContent = `Streaming... (${tokenCount} tokens)`;
          }
        }

        if (chunk.done) {
          // Use stats from the engine
          if (chunk.stats) {
            document.getElementById('metric-speed').textContent = `${chunk.stats.tokensPerSecond.toFixed(1)} tok/s`;
          }
          break;
        }
      }
    } else {
      // ===== Demo mode: simulate streaming =====
      const demoResponse = generateDemoResponse(prompt);
      const words = demoResponse.split('');

      for (let i = 0; i < words.length && isStreaming; i++) {
        await sleep(15 + Math.random() * 25);

        if (!receivedFirst) {
          document.getElementById('metric-ttft').textContent = `${Math.round(performance.now() - start)}ms`;
          receivedFirst = true;
        }

        accumulated += words[i];
        tokenCount++;
        updateStreamingBubble(accumulated);

        if (tokenCount % 10 === 0) {
          statusText.textContent = `Streaming... (${tokenCount} tokens)`;
        }
      }
    }

    // Finalize
    finalizeStreamingBubble(accumulated);
    messages.push({ role: 'assistant', content: accumulated });

    const elapsed = (performance.now() - start) / 1000;
    const tps = tokenCount > 0 ? tokenCount / elapsed : 0;

    if (!document.getElementById('metric-speed').textContent.includes('tok/s')) {
      document.getElementById('metric-speed').textContent = `${tps.toFixed(1)} tok/s`;
    }

    // Memory usage from engine or estimate
    if (edgeVeda && typeof edgeVeda.getMemoryUsage === 'function') {
      try {
        const mem = await edgeVeda.getMemoryUsage();
        document.getElementById('metric-memory').textContent = `${Math.round(mem.total / (1024 * 1024))} MB`;
      } catch {
        document.getElementById('metric-memory').textContent = '~256 MB';
      }
    } else {
      document.getElementById('metric-memory').textContent = '~256 MB';
    }

    statusText.textContent = `Complete (${tokenCount} tokens, ${tps.toFixed(1)} tok/s)`;
    statusText.className = 'status-text success';
  } catch (e) {
    console.error('Generation error:', e);
    statusText.textContent = `Error: ${e.message}`;
    statusText.className = 'status-text warning';

    if (accumulated) {
      finalizeStreamingBubble(accumulated);
      messages.push({ role: 'assistant', content: accumulated });
    }
  }

  isStreaming = false;
  sendBtn.textContent = '↑';
  sendBtn.classList.remove('stop');
  sendBtn.onclick = sendMessage;
  updateContextIndicator();
}

/**
 * Builds a prompt string with chat template for the model.
 */
function buildPrompt(userMessage) {
  const systemPrompts = {
    assistant: 'You are a helpful assistant.',
    coder: 'You are a coding assistant. Provide clear, working code examples.',
    creative: 'You are a creative writing assistant. Be imaginative and expressive.',
  };

  const systemPrompt = systemPrompts[currentPreset] || systemPrompts.assistant;

  // Build conversation context (Llama 3 chat template)
  let prompt = `<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n${systemPrompt}<|eot_id|>`;

  // Add conversation history (last 10 exchanges)
  const recentMessages = messages.slice(-20);
  for (const msg of recentMessages) {
    if (msg.role === 'user') {
      prompt += `<|start_header_id|>user<|end_header_id|>\n\n${msg.content}<|eot_id|>`;
    } else if (msg.role === 'assistant') {
      prompt += `<|start_header_id|>assistant<|end_header_id|>\n\n${msg.content}<|eot_id|>`;
    }
  }

  // Add current user message
  prompt += `<|start_header_id|>user<|end_header_id|>\n\n${userMessage}<|eot_id|>`;
  prompt += `<|start_header_id|>assistant<|end_header_id|>\n\n`;

  return prompt;
}

function cancelGeneration() {
  isStreaming = false;
  if (edgeVeda && typeof edgeVeda.cancelGeneration === 'function') {
    edgeVeda.cancelGeneration().catch(() => {});
  }
  document.getElementById('status-text').textContent = 'Cancelled';
}

function resetChat() {
  messages = [];
  if (edgeVeda && typeof edgeVeda.resetContext === 'function') {
    edgeVeda.resetContext().catch(() => {});
  }
  const messagesEl = document.getElementById('messages');
  messagesEl.innerHTML = `
    <div class="empty-state">
      <div class="empty-icon">💭</div>
      <div class="empty-title">Start a conversation</div>
      <div class="empty-sub">Ask anything. It runs in your browser.</div>
    </div>`;
  document.getElementById('metric-ttft').textContent = '-';
  document.getElementById('metric-speed').textContent = '-';
  document.getElementById('metric-memory').textContent = '-';
  document.getElementById('persona-picker').classList.remove('hidden');
  document.getElementById('context-indicator').classList.add('hidden');
  document.getElementById('status-text').textContent = 'Ready to chat!';
  document.getElementById('status-text').className = 'status-text success';
}

function changePreset(preset) {
  currentPreset = preset;
  document.querySelectorAll('.chip').forEach((c) => c.classList.remove('active'));
  document.querySelector(`.chip[data-preset="${preset}"]`).classList.add('active');

  // Recreate ChatSession with new preset if SDK is loaded
  if (chatSession && SDK && SDK.ChatSession) {
    chatSession = new SDK.ChatSession(edgeVeda, preset);
  }
}

// ======================== Message Rendering ========================
function addMessage(role, content) {
  messages.push({ role, content });
  const messagesEl = document.getElementById('messages');
  const row = document.createElement('div');
  row.className = `message-row ${role}`;

  if (role === 'user') {
    row.innerHTML = `<div class="bubble user">${escapeHtml(content)}</div><div class="avatar">👤</div>`;
  } else if (role === 'assistant') {
    row.innerHTML = `<div class="avatar">✨</div><div class="bubble assistant">${escapeHtml(content)}</div>`;
  } else {
    row.innerHTML = `<div class="bubble system">${escapeHtml(content)}</div>`;
  }

  messagesEl.appendChild(row);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function updateStreamingBubble(text) {
  const messagesEl = document.getElementById('messages');
  let streamingRow = document.getElementById('streaming-bubble');

  if (!streamingRow) {
    streamingRow = document.createElement('div');
    streamingRow.className = 'message-row assistant';
    streamingRow.id = 'streaming-bubble';
    streamingRow.innerHTML = `<div class="avatar">✨</div><div class="bubble assistant" id="streaming-text"></div>`;
    messagesEl.appendChild(streamingRow);
  }

  document.getElementById('streaming-text').textContent = text;
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function finalizeStreamingBubble(text) {
  const streamingRow = document.getElementById('streaming-bubble');
  if (streamingRow) {
    streamingRow.id = '';
    const bubble = streamingRow.querySelector('.bubble');
    if (bubble) {
      bubble.id = '';
      bubble.textContent = text;
    }
  }
}

function clearEmptyState() {
  const empty = document.querySelector('.empty-state');
  if (empty) empty.remove();
}

function updateContextIndicator() {
  const indicator = document.getElementById('context-indicator');
  const turns = messages.filter((m) => m.role === 'user').length;
  const usage = Math.min(1, turns / 20);

  indicator.classList.remove('hidden');
  document.getElementById('context-turns').textContent = `${turns} ${turns === 1 ? 'turn' : 'turns'}`;
  document.getElementById('context-bar-fill').style.width = `${usage * 100}%`;
  document.getElementById('context-pct').textContent = `${Math.round(usage * 100)}%`;

  if (usage > 0.8) {
    document.getElementById('context-bar-fill').style.background = 'var(--warning)';
    document.getElementById('context-pct').style.color = 'var(--warning)';
  } else {
    document.getElementById('context-bar-fill').style.background = 'var(--accent)';
    document.getElementById('context-pct').style.color = 'var(--text-tertiary)';
  }
}

// ======================== Model Sheet ========================
function showModelSheet() {
  document.getElementById('model-modal').classList.remove('hidden');
  populateModelList();
}

function hideModelSheet() {
  document.getElementById('model-modal').classList.add('hidden');
}

async function populateModelList() {
  const list = document.getElementById('model-list');
  const models = [
    { id: 'llama-3.2-1b-q4_k_m', name: 'Llama 3.2 1B Instruct', size: '~750 MB', quant: 'Q4_K_M', icon: '🤖' },
    { id: 'smolvlm2-500m', name: 'SmolVLM2 500M', size: '~350 MB', quant: 'Q4_K_M', icon: '👁️' },
    { id: 'smolvlm2-500m-mmproj', name: 'SmolVLM2 mmproj', size: '~90 MB', quant: 'F16', icon: '🧩' },
  ];

  // Check cache status for each model
  const modelHtml = [];
  for (const m of models) {
    let cached = false;
    try {
      if (SDK && SDK.getCachedModel) {
        cached = !!(await SDK.getCachedModel(m.id));
      }
    } catch {}

    modelHtml.push(`
      <div class="model-card">
        <div class="model-icon-box">${m.icon}</div>
        <div class="model-info">
          <div class="model-name">${m.name}</div>
          <div class="model-meta">${m.size} • ${m.quant}</div>
        </div>
        <div class="status-circle ${cached ? 'green' : 'teal'}">${cached ? '✓' : '↓'}</div>
      </div>`);
  }

  list.innerHTML = modelHtml.join('');
}

// ======================== Demo Response Generator ========================
/**
 * Fallback demo response generator for when the WASM model isn't loaded.
 * Provides realistic-feeling responses to demonstrate the UI.
 */
function generateDemoResponse(prompt) {
  const lower = prompt.toLowerCase();

  if (lower.includes('hello') || lower.includes('hi')) {
    return "Hello! I'm Veda, running entirely in your browser using WebAssembly. No data is sent to any server — everything stays on your device. How can I help you today?";
  }
  if (lower.includes('what') && lower.includes('you')) {
    return "I'm an on-device AI assistant powered by Edge Veda. I run locally in your browser using a quantized Llama 3.2 1B model loaded via WebAssembly. This means:\n\n• Complete privacy — no data leaves your device\n• Works offline after model download\n• Low latency with no server round-trips\n\nI can help with questions, coding, creative writing, and more!";
  }
  if (lower.includes('code') || lower.includes('function') || lower.includes('program')) {
    return "Here's a practical example — a debounce utility:\n\nfunction debounce(fn, delay) {\n  let timer;\n  return (...args) => {\n    clearTimeout(timer);\n    timer = setTimeout(() => fn(...args), delay);\n  };\n}\n\n// Usage:\nconst search = debounce((query) => {\n  console.log('Searching:', query);\n}, 300);\n\nThis is running locally via WASM — zero latency to any server!";
  }
  if (lower.includes('weather')) {
    return "I don't have access to real-time data since I run entirely offline in your browser. However, I can tell you about weather patterns, climate science, or help you build a weather app that fetches data from an API!";
  }
  if (lower.includes('capital')) {
    return "The capital of France is Paris, located along the Seine River. Founded in the 3rd century BC by a Celtic people called the Parisii, it has been a major European city for over 2,000 years. Notable landmarks include the Eiffel Tower (1889), the Louvre Museum (world's largest art museum), and Notre-Dame Cathedral (currently under restoration after the 2019 fire).";
  }
  if (lower.includes('explain') || lower.includes('how does')) {
    return "Great question! Let me break this down:\n\nThis demo loads a GGUF-quantized Llama 3.2 1B model directly in your browser. Here's how it works:\n\n1. **Download**: The ~750MB Q4_K_M model is fetched from HuggingFace\n2. **Cache**: Stored in IndexedDB so it's instant next time\n3. **WASM Engine**: llama.cpp compiled to WebAssembly runs inference\n4. **Streaming**: Tokens are generated one-by-one via Web Workers\n5. **Chat Template**: Llama 3 instruct format wraps your messages\n\nAll computation happens in your browser's WebAssembly runtime. No GPU required (though WebGPU accelerates it when available).";
  }

  return `That's a great question! As an on-device AI running in your browser via WebAssembly, I can process your queries with complete privacy.\n\nIn this demo, I'm using a quantized Llama 3.2 1B Instruct model (Q4_K_M format, ~750MB). The model is:\n\n• Downloaded once from HuggingFace and cached in IndexedDB\n• Loaded into a Web Worker for background inference\n• Running via llama.cpp compiled to WebAssembly\n• Streaming tokens back to the UI in real-time\n\nThe Edge Veda Web SDK handles model caching, WASM initialization, streaming generation, and chat session management — all running locally with zero server calls.`;
}

// ======================== Utilities ========================
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ======================== Auto-resize textarea ========================
document.addEventListener('DOMContentLoaded', () => {
  const textarea = document.getElementById('prompt-input');
  if (textarea) {
    textarea.addEventListener('input', () => {
      textarea.style.height = 'auto';
      textarea.style.height = Math.min(textarea.scrollHeight, 100) + 'px';
    });
    textarea.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
      }
    });
  }
});
