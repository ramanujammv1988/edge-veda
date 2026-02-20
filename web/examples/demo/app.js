/**
 * Edge Veda Web Demo — Application Logic
 *
 * Loads a GGUF model via WASM and generates text in-browser.
 * Uses the Edge Veda Web SDK (EdgeVeda, ChatSession, model-cache).
 * Demonstrates: Chat, Voice (Whisper), Tools, RAG, Vision
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

// Voice/STT state
let whisperWorker = null;
let isRecording = false;
let mediaRecorder = null;
let audioChunks = [];

// Tools state
let toolRegistry = null;
let toolsEnabled = false;
let toolMessages = [];

// RAG state
let ragPipeline = null;
let vectorIndex = null;
let ragEmbedder = null;
let attachedDocName = null;
let attachedChunkCount = 0;
let ragMessages = [];

// Vision state
let visionWorker = null;
let cameraStream = null;
let visionInterval = null;

// Benchmark state
let runningBenchmark = false;

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
    SDK = await import('../../src/index.js');
    const EdgeVeda = SDK.default || SDK.EdgeVeda;
    const ChatSession = SDK.ChatSession;

    statusText.textContent = 'Checking model cache...';

    const hasCached = await SDK.getCachedModel(MODEL_CONFIG.modelId);
    if (!hasCached) {
      statusText.textContent = 'Downloading GGUF model (~750 MB)...';

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

    statusText.textContent = 'Initializing WASM inference engine...';

    edgeVeda = new EdgeVeda({
      modelId: MODEL_CONFIG.modelId,
      device: 'auto',
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

    if (ChatSession) {
      chatSession = new ChatSession(edgeVeda, currentPreset);
    }

    if (SDK.ToolRegistry && SDK.ToolDefinition) {
      const demoTools = [
        new SDK.ToolDefinition({
          name: 'get_time',
          description: 'Get the current date and time for a location',
          parameters: {
            type: 'object',
            properties: {
              location: { type: 'string', description: 'City or region' },
            },
            required: ['location'],
          },
        }),
        new SDK.ToolDefinition({
          name: 'calculate',
          description: 'Perform a math calculation',
          parameters: {
            type: 'object',
            properties: {
              expression: { type: 'string', description: 'Math expression' },
            },
            required: ['expression'],
          },
        }),
      ];
      toolRegistry = new SDK.ToolRegistry(demoTools);
      updateToolsDisplay();
    }

    isInitialized = true;
    statusText.textContent = 'Ready to chat!';
    statusText.className = 'status-text success';
    statusSpinner.classList.add('hidden');

    promptInput.disabled = false;
    sendBtn.disabled = false;
    document.getElementById('metrics-bar').classList.remove('hidden');
    document.getElementById('persona-picker').classList.remove('hidden');

    populateModelList();
  } catch (e) {
    console.error('Initialization error:', e);
    statusText.textContent = `SDK init failed: ${e.message}. Running in demo mode.`;
    statusText.className = 'status-text warning';
    statusSpinner.classList.add('hidden');

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
  let totalConfidence = 0;
  let confidenceCount = 0;

  const temperature = parseFloat(document.getElementById('temp-slider').value) || 0.7;
  const maxTokens = parseInt(document.getElementById('tokens-slider').value) || 256;

  try {
    if (edgeVeda && typeof edgeVeda.generateStream === 'function') {
      const generateOptions = {
        prompt: buildPrompt(prompt),
        maxTokens,
        temperature,
        topP: 0.9,
        topK: 40,
      };

      for await (const chunk of edgeVeda.generateStream(generateOptions)) {
        if (!isStreaming) break;

        if (!receivedFirst && chunk.token) {
          document.getElementById('metric-ttft').textContent = `${Math.round(performance.now() - start)}ms`;
          receivedFirst = true;
        }

        if (chunk.token) {
          accumulated += chunk.token;
          tokenCount++;
          updateStreamingBubble(accumulated);

          if (chunk.confidence != null) {
            totalConfidence += chunk.confidence;
            confidenceCount++;
          }

          if (tokenCount % 5 === 0) {
            statusText.textContent = `Streaming... (${tokenCount} tokens)`;
          }
        }

        if (chunk.done) {
          if (chunk.stats) {
            document.getElementById('metric-speed').textContent = `${chunk.stats.tokensPerSecond.toFixed(1)} tok/s`;
          }
          break;
        }
      }
    } else {
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

    finalizeStreamingBubble(accumulated);
    messages.push({ role: 'assistant', content: accumulated });

    const elapsed = (performance.now() - start) / 1000;
    const tps = tokenCount > 0 ? tokenCount / elapsed : 0;

    if (!document.getElementById('metric-speed').textContent.includes('tok/s')) {
      document.getElementById('metric-speed').textContent = `${tps.toFixed(1)} tok/s`;
    }

    if (confidenceCount > 0) {
      const avgConfidence = totalConfidence / confidenceCount;
      document.getElementById('metric-confidence').textContent = `${(avgConfidence * 100).toFixed(0)}%`;
    }

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

function buildPrompt(userMessage) {
  const systemPrompts = {
    assistant: 'You are a helpful assistant.',
    coder: 'You are a coding assistant. Provide clear, working code examples.',
    creative: 'You are a creative writing assistant. Be imaginative and expressive.',
  };

  const systemPrompt = systemPrompts[currentPreset] || systemPrompts.assistant;

  let prompt = `<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n${systemPrompt}<|eot_id|>`;

  const recentMessages = messages.slice(-20);
  for (const msg of recentMessages) {
    if (msg.role === 'user') {
      prompt += `<|start_header_id|>user<|end_header_id|>\n\n${msg.content}<|eot_id|>`;
    } else if (msg.role === 'assistant') {
      prompt += `<|start_header_id|>assistant<|end_header_id|>\n\n${msg.content}<|eot_id|>`;
    }
  }

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
  document.getElementById('metric-confidence').textContent = '-';
  document.getElementById('persona-picker').classList.remove('hidden');
  document.getElementById('context-indicator').classList.add('hidden');
  document.getElementById('status-text').textContent = 'Ready to chat!';
  document.getElementById('status-text').className = 'status-text success';
}

function changePreset(preset) {
  currentPreset = preset;
  document.querySelectorAll('.chip').forEach((c) => c.classList.remove('active'));
  document.querySelector(`.chip[data-preset="${preset}"]`).classList.add('active');

  if (chatSession && SDK && SDK.ChatSession) {
    chatSession = new SDK.ChatSession(edgeVeda, preset);
  }
}

// ======================== Voice/STT Tab ========================
async function toggleVoiceRecording() {
  if (!isInitialized) {
    alert('Please initialize the engine first');
    return;
  }

  if (isRecording) {
    stopRecording();
  } else {
    await startRecording();
  }
}

async function startRecording() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    mediaRecorder = new MediaRecorder(stream);
    audioChunks = [];

    mediaRecorder.ondataavailable = (event) => {
      audioChunks.push(event.data);
    };

    mediaRecorder.onstop = async () => {
      const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
      await transcribeAudio(audioBlob);
      stream.getTracks().forEach(track => track.stop());
    };

    mediaRecorder.start();
    isRecording = true;

    const recordBtn = document.getElementById('voice-record-btn');
    recordBtn.textContent = 'Stop Recording';
    recordBtn.classList.add('recording');
    
    document.getElementById('voice-status').textContent = 'Recording...';
    document.getElementById('voice-status').style.color = '#EF5350';
  } catch (e) {
    console.error('Microphone error:', e);
    alert('Could not access microphone: ' + e.message);
  }
}

function stopRecording() {
  if (mediaRecorder && isRecording) {
    mediaRecorder.stop();
    isRecording = false;

    const recordBtn = document.getElementById('voice-record-btn');
    recordBtn.textContent = 'Start Recording';
    recordBtn.classList.remove('recording');
    
    document.getElementById('voice-status').textContent = 'Processing...';
    document.getElementById('voice-status').style.color = '#00BCD4';
  }
}

async function transcribeAudio(audioBlob) {
  try {
    document.getElementById('voice-status').textContent = 'Transcribing...';
    
    if (!whisperWorker && SDK.WhisperWorker) {
      whisperWorker = new SDK.WhisperWorker();
      await whisperWorker.init();
    }

    if (whisperWorker) {
      const result = await whisperWorker.transcribe(audioBlob);
      
      const transcriptArea = document.getElementById('voice-transcript');
      transcriptArea.value = result.text || 'No speech detected';
      
      document.getElementById('voice-status').textContent = 'Transcription complete';
      document.getElementById('voice-status').style.color = '#66BB6A';
    } else {
      document.getElementById('voice-transcript').value = '[Demo mode] Whisper transcription would appear here';
      document.getElementById('voice-status').textContent = 'Demo mode (Whisper not loaded)';
    }
  } catch (e) {
    console.error('Transcription error:', e);
    document.getElementById('voice-status').textContent = 'Transcription failed';
    document.getElementById('voice-status').style.color = '#EF5350';
  }
}

function clearVoiceTranscript() {
  document.getElementById('voice-transcript').value = '';
  document.getElementById('voice-status').textContent = 'Ready to record';
  document.getElementById('voice-status').style.color = '#F5F5F5';
}

// ======================== Tools Tab ========================
function updateToolsDisplay() {
  if (!toolRegistry) return;

  const toolsList = document.getElementById('tools-list');
  const tools = toolRegistry.getTools();
  
  toolsList.innerHTML = tools.map(tool => `
    <div class="tool-chip">
      <span class="tool-name">${tool.name}</span>
      <span class="tool-desc">${tool.description}</span>
    </div>
  `).join('');
}

async function sendToolsMessage() {
  const input = document.getElementById('tools-input');
  const prompt = input.value.trim();
  if (!prompt || !isInitialized) return;

  input.value = '';
  
  addToolMessage('user', prompt);
  document.getElementById('tools-status').textContent = 'Calling tools...';

  try {
    const response = await chatSession.sendWithTools(
      prompt,
      (toolCall) => handleToolCall(toolCall),
      {
        maxTokens: 256,
        temperature: 0.7,
      }
    );

    addToolMessage('assistant', response.content);
    document.getElementById('tools-status').textContent = 'Complete';
  } catch (e) {
    console.error('Tool calling error:', e);
    document.getElementById('tools-status').textContent = 'Error: ' + e.message;
    
    const demoResponse = handleDemoToolCall(prompt);
    addToolMessage('assistant', demoResponse);
  }
}

function handleToolCall(toolCall) {
  addToolMessage('tool-call', JSON.stringify(toolCall, null, 2));
  
  let result;
  
  if (toolCall.name === 'get_time') {
    const location = toolCall.arguments.location || 'UTC';
    const now = new Date();
    result = {
      local_time: now.toLocaleTimeString(),
      date: now.toLocaleDateString(),
      location: location,
      utc_offset: (-now.getTimezoneOffset() / 60).toString(),
    };
  } else if (toolCall.name === 'calculate') {
    const expr = toolCall.arguments.expression || '';
    try {
      const safeExpr = expr.replace(/[^0-9+\-*/().]/g, '');
      result = { result: eval(safeExpr), expression: expr };
    } catch {
      result = { error: 'Invalid expression', expression: expr };
    }
  } else {
    result = { error: 'Unknown tool: ' + toolCall.name };
  }
  
  addToolMessage('tool-result', JSON.stringify(result, null, 2));
  
  return SDK.ToolResult.success(toolCall.id, result);
}

function handleDemoToolCall(prompt) {
  const lower = prompt.toLowerCase();
  
  if (lower.includes('time') || lower.includes('clock')) {
    const now = new Date();
    return `The current time is ${now.toLocaleTimeString()}. Date: ${now.toLocaleDateString()}.`;
  }
  
  if (lower.includes('calculate') || lower.includes('math')) {
    return `I can perform calculations. For example, 2+2 = 4, or sqrt(16) = 4.`;
  }
  
  return `I have access to tools like get_time() and calculate(). Try asking "What time is it?" or "Calculate 2+2".`;
}

function addToolMessage(role, content) {
  toolMessages.push({ role, content });
  
  const messagesEl = document.getElementById('tools-messages');
  const msg = document.createElement('div');
  msg.className = `tool-message ${role}`;
  
  if (role === 'tool-call') {
    msg.innerHTML = `<div class="tool-label">🔧 Tool Call</div><pre>${escapeHtml(content)}</pre>`;
  } else if (role === 'tool-result') {
    msg.innerHTML = `<div class="tool-label">✓ Tool Result</div><pre>${escapeHtml(content)}</pre>`;
  } else if (role === 'user') {
    msg.innerHTML = `<div class="tool-label">You</div><div>${escapeHtml(content)}</div>`;
  } else {
    msg.innerHTML = `<div class="tool-label">Assistant</div><div>${escapeHtml(content)}</div>`;
  }
  
  messagesEl.appendChild(msg);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function resetToolsChat() {
  toolMessages = [];
  document.getElementById('tools-messages').innerHTML = '';
  document.getElementById('tools-status').textContent = 'Ready';
}

// ======================== RAG Tab ========================
async function loadRagDocument() {
  const fileInput = document.getElementById('rag-file-input');
  const file = fileInput.files[0];
  
  if (!file) {
    alert('Please select a file');
    return;
  }

  document.getElementById('rag-status').textContent = 'Loading document...';

  try {
    const text = await file.text();
    const chunks = chunkText(text);
    
    document.getElementById('rag-status').textContent = 'Embedding chunks...';

    if (!ragEmbedder && SDK.RagPipeline) {
      ragPipeline = await SDK.RagPipeline.withModels();
      ragEmbedder = ragPipeline;
    }

    if (ragEmbedder && SDK.VectorIndex) {
      vectorIndex = new SDK.VectorIndex(384);
      
      for (const chunk of chunks) {
        const embedding = await ragEmbedder.embed(chunk);
        vectorIndex.add(embedding, chunk);
      }
      
      attachedDocName = file.name;
      attachedChunkCount = chunks.length;
      
      document.getElementById('rag-doc-name').textContent = file.name;
      document.getElementById('rag-chunk-count').textContent = `${chunks.length} chunks`;
      document.getElementById('rag-status').textContent = 'Document ready';
      document.getElementById('rag-status').style.color = '#66BB6A';
    } else {
      document.getElementById('rag-status').textContent = 'Demo mode (embeddings not available)';
      attachedDocName = file.name;
      attachedChunkCount = chunks.length;
      document.getElementById('rag-doc-name').textContent = file.name;
      document.getElementById('rag-chunk-count').textContent = `${chunks.length} chunks`;
    }
  } catch (e) {
    console.error('RAG loading error:', e);
    document.getElementById('rag-status').textContent = 'Error: ' + e.message;
    document.getElementById('rag-status').style.color = '#EF5350';
  }
}

function chunkText(text) {
  const chunkSize = 500;
  const overlap = 50;
  const chunks = [];
  
  let start = 0;
  while (start < text.length) {
    const end = Math.min(start + chunkSize, text.length);
    chunks.push(text.substring(start, end));
    start += chunkSize - overlap;
  }
  
  return chunks;
}

async function sendRagMessage() {
  const input = document.getElementById('rag-input');
  const prompt = input.value.trim();
  if (!prompt || !isInitialized) return;

  input.value = '';
  
  addRagMessage('user', prompt);
  document.getElementById('rag-status').textContent = 'Searching...';

  try {
    let context = '';
    
    if (vectorIndex && ragEmbedder) {
      const queryEmbedding = await ragEmbedder.embed(prompt);
      const results = vectorIndex.search(queryEmbedding, 3);
      context = results.map(r => r.content).join('\n\n');
    }

    const augmentedPrompt = context
      ? `Context:\n${context}\n\nQuestion: ${prompt}`
      : prompt;

    document.getElementById('rag-status').textContent = 'Generating...';

    let response = '';
    if (edgeVeda && typeof edgeVeda.generateStream === 'function') {
      for await (const chunk of edgeVeda.generateStream({
        prompt: augmentedPrompt,
        maxTokens: 256,
        temperature: 0.7,
      })) {
        if (chunk.token) {
          response += chunk.token;
        }
        if (chunk.done) break;
      }
    } else {
      response = `Based on the document, ${generateDemoResponse(prompt)}`;
    }

    addRagMessage('assistant', response);
    document.getElementById('rag-status').textContent = 'Complete';
  } catch (e) {
    console.error('RAG error:', e);
    document.getElementById('rag-status').textContent = 'Error: ' + e.message;
    addRagMessage('assistant', 'Error processing query');
  }
}

function addRagMessage(role, content) {
  ragMessages.push({ role, content });
  
  const messagesEl = document.getElementById('rag-messages');
  const msg = document.createElement('div');
  msg.className = `rag-message ${role}`;
  msg.textContent = content;
  
  messagesEl.appendChild(msg);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function resetRagChat() {
  ragMessages = [];
  document.getElementById('rag-messages').innerHTML = '';
  document.getElementById('rag-status').textContent = 'Ready';
}

// ======================== Vision Tab ========================
async function toggleCamera() {
  if (!isInitialized) {
    alert('Please initialize the engine first');
    return;
  }

  if (cameraStream) {
    cameraStream.getTracks().forEach(track => track.stop());
    cameraStream = null;
    document.getElementById('vision-video').srcObject = null;
    document.getElementById('vision-camera-btn').textContent = 'Start Camera';
    document.getElementById('vision-status').textContent = 'Camera stopped';
    
    if (visionInterval) {
      clearInterval(visionInterval);
      visionInterval = null;
    }
  } else {
    try {
      cameraStream = await navigator.mediaDevices.getUserMedia({ video: true });
      const video = document.getElementById('vision-video');
      video.srcObject = cameraStream;
      video.play();
      
      document.getElementById('vision-camera-btn').textContent = 'Stop Camera';
      document.getElementById('vision-status').textContent = 'Camera active';
      document.getElementById('vision-status').style.color = '#66BB6A';
    } catch (e) {
      console.error('Camera error:', e);
      alert('Could not access camera: ' + e.message);
    }
  }
}

// ======================== Benchmark Tab ========================
async function runBenchmark() {
  if (!isInitialized || runningBenchmark) return;

  runningBenchmark = true;
  showBenchmarkModal();

  const iterations = 10;
  const testPrompt = 'Explain quantum computing in one sentence.';
  const results = [];

  document.getElementById('benchmark-progress').textContent = 'Running...';

  for (let i = 0; i < iterations; i++) {
    const start = performance.now();
    let tokenCount = 0;
    let firstTokenTime = null;

    try {
      if (edgeVeda && typeof edgeVeda.generateStream === 'function') {
        for await (const chunk of edgeVeda.generateStream({
          prompt: testPrompt,
          maxTokens: 50,
          temperature: 0.7,
        })) {
          if (chunk.token) {
            tokenCount++;
            if (firstTokenTime === null) {
              firstTokenTime = performance.now() - start;
            }
          }
          if (chunk.done) break;
        }
      } else {
        await sleep(500);
        tokenCount = 50;
        firstTokenTime = 50;
      }

      const totalTime = performance.now() - start;
      const tokensPerSecond = tokenCount / (totalTime / 1000);

      results.push({
        iteration: i + 1,
        ttft: firstTokenTime,
        totalTime,
        tokenCount,
        tokensPerSecond,
      });

      document.getElementById('benchmark-progress').textContent = `${i + 1}/${iterations} complete`;
    } catch (e) {
      console.error('Benchmark error:', e);
      results.push({
        iteration: i + 1,
        error: e.message,
      });
    }
  }

  const validResults = results.filter(r => !r.error);
  const avgTtft = validResults.reduce((sum, r) => sum + r.ttft, 0) / validResults.length;
  const avgTps = validResults.reduce((sum, r) => sum + r.tokensPerSecond, 0) / validResults.length;

  document.getElementById('benchmark-results').innerHTML = `
    <div><strong>Average TTFT:</strong> ${avgTtft.toFixed(0)}ms</div>
    <div><strong>Average Speed:</strong> ${avgTps.toFixed(1)} tok/s</div>
    <div><strong>Runs:</strong> ${validResults.length}/${iterations}</div>
  `;

  document.getElementById('benchmark-progress').textContent = 'Complete';
  runningBenchmark = false;
}

function showBenchmarkModal() {
  document.getElementById('benchmark-modal').classList.add('active');
}

function hideBenchmarkModal() {
  document.getElementById('benchmark-modal').classList.remove('active');
}

// ======================== Settings ========================
function updateHandoffThreshold() {
  const value = document.getElementById('handoff-slider').value;
  document.getElementById('handoff-value').textContent = value;
}

// ======================== Message Rendering ========================
function addMessage(role, content) {
  messages.push({ role, content });
  
  const messagesEl = document.getElementById('messages');
  const msg = document.createElement('div');
  msg.className = `message ${role}`;
  msg.textContent = content;
  
  messagesEl.appendChild(msg);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function updateStreamingBubble(content) {
  const messagesEl = document.getElementById('messages');
  let bubble = messagesEl.querySelector('.message.assistant.streaming');
  
  if (!bubble) {
    bubble = document.createElement('div');
    bubble.className = 'message assistant streaming';
    messagesEl.appendChild(bubble);
  }
  
  bubble.textContent = content;
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function finalizeStreamingBubble(content) {
  const messagesEl = document.getElementById('messages');
  const bubble = messagesEl.querySelector('.message.assistant.streaming');
  
  if (bubble) {
    bubble.classList.remove('streaming');
    bubble.textContent = content;
  }
}

// ======================== Utility Functions ========================
function clearEmptyState() {
  const emptyState = document.querySelector('.empty-state');
  if (emptyState) {
    emptyState.remove();
  }
}

function updateContextIndicator() {
  const indicator = document.getElementById('context-indicator');
  const tokenCount = messages.reduce((sum, msg) => sum + msg.content.length / 4, 0);
  
  indicator.textContent = `${Math.round(tokenCount)} / 2048 tokens`;
  indicator.classList.remove('hidden');
}

function showModelSheet() {
  document.getElementById('model-sheet').classList.add('active');
}

function hideModelSheet() {
  document.getElementById('model-sheet').classList.remove('active');
}

function populateModelList() {
  const list = document.getElementById('model-list');
  list.innerHTML = `
    <div class="model-item active">
      <div class="model-name">${MODEL_CONFIG.name}</div>
      <div class="model-meta">${MODEL_CONFIG.quantization} • ${(MODEL_CONFIG.sizeBytes / (1024 * 1024 * 1024)).toFixed(1)}GB</div>
    </div>
  `;
}

function generateDemoResponse(prompt) {
  const responses = [
    "I'm running in demo mode since the SDK couldn't be loaded. In a real deployment, I would generate contextual responses based on the GGUF model.",
    "This is a simulated response. The actual SDK would use WASM inference with the loaded model to generate real responses.",
    "Demo mode active. Once the SDK loads successfully, I'll provide genuine AI-generated responses using the Llama model.",
  ];
  return responses[Math.floor(Math.random() * responses.length)];
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// ======================== Event Listeners ========================
document.addEventListener('DOMContentLoaded', () => {
  const promptInput = document.getElementById('prompt-input');
  
  promptInput.addEventListener('input', function() {
    this.style.height = 'auto';
    this.style.height = Math.min(this.scrollHeight, 120) + 'px';
  });
  
  promptInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  });
  
  const toolsInput = document.getElementById('tools-input');
  toolsInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendToolsMessage();
    }
  });
  
  const ragInput = document.getElementById('rag-input');
  ragInput.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendRagMessage();
    }
  });
});
