# Edge-Veda SDK Implementation Roadmap

**Version:** 1.0  
**Last Updated:** November 2, 2026  
**Status:** Active Development

---

## Overview

This document outlines the concrete implementation plan for achieving SDK feature parity across all Edge-Veda platforms. Work is organized into phases with clear priorities and success criteria.

---

## Current Status Summary

- ✅ **Build System:** All platforms compile with 0 errors, 0 warnings
- ✅ **Flutter SDK:** 100% feature complete (reference implementation)
- ⚠️ **Other SDKs:** Core APIs functional, advanced features missing

See [SDK_FEATURE_PARITY_ANALYSIS.md](SDK_FEATURE_PARITY_ANALYSIS.md) for detailed gap analysis.

---

## Phase 1: Core API Completion (ACTIVE)

**Timeline:** 1-2 weeks  
**Priority:** 🔴 **CRITICAL**  
**Goal:** 100% Tier 1 feature parity across all platforms

### 1.1 Kotlin SDK Core APIs

**Status:** 🔄 In Progress

#### Missing Features

- [ ] `getModelInfo()` - Get model metadata
- [ ] `resetContext()` - Reset conversation context
- [ ] `isModelLoaded()` - Check if model is loaded
- [ ] `cancelGeneration()` - Replace placeholder with real implementation

#### Implementation Details

**1.1.1 getModelInfo() Implementation**

```kotlin
// In EdgeVeda.kt
suspend fun getModelInfo(): ModelInfo {
    checkInitialized()
    
    return withContext(Dispatchers.Default) {
        try {
            val infoMap = nativeBridge.getModelInfo()
            ModelInfo(
                name = infoMap["name"] ?: "unknown",
                architecture = infoMap["arch"] ?: "unknown",
                parameterCount = infoMap["n_params"]?.toLongOrNull() ?: 0L,
                contextLength = infoMap["n_ctx"]?.toIntOrNull() ?: 0,
                vocabSize = infoMap["n_vocab"]?.toIntOrNull() ?: 0,
                quantization = infoMap["quantization"] ?: "unknown"
            )
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError(
                "Failed to get model info: ${e.message}", 
                e
            )
        }
    }
}

// Add ModelInfo data class to types
data class ModelInfo(
    val name: String,
    val architecture: String,
    val parameterCount: Long,
    val contextLength: Int,
    val vocabSize: Int,
    val quantization: String
)
```

**1.1.2 resetContext() Implementation**

```kotlin
// In EdgeVeda.kt
suspend fun resetContext() {
    checkInitialized()
    
    withContext(Dispatchers.Default) {
        try {
            nativeBridge.resetContext()
        } catch (e: Exception) {
            throw EdgeVedaException.GenerationError(
                "Failed to reset context: ${e.message}", 
                e
            )
        }
    }
}

// In NativeBridge.kt
external fun resetContext()
```

**1.1.3 isModelLoaded() Implementation**

```kotlin
// In EdgeVeda.kt
fun isModelLoaded(): Boolean {
    return initialized.get() && !closed.get()
}
```

**1.1.4 cancelGeneration() Implementation**

```kotlin
// In EdgeVeda.kt
private val currentGenerationId = AtomicReference<String?>(null)

suspend fun cancelGeneration() {
    checkInitialized()
    
    val genId = currentGenerationId.getAndSet(null)
    if (genId != null) {
        withContext(Dispatchers.Default) {
            try {
                nativeBridge.cancelGeneration(genId)
            } catch (e: Exception) {
                throw EdgeVedaException.GenerationError(
                    "Failed to cancel generation: ${e.message}", 
                    e
                )
            }
        }
    }
}

// Update generateStream to track generation ID
fun generateStream(
    prompt: String,
    options: GenerateOptions = GenerateOptions()
): Flow<String> = flow {
    checkInitialized()
    
    val genId = UUID.randomUUID().toString()
    currentGenerationId.set(genId)
    
    try {
        nativeBridge.generateStream(prompt, options, genId) { token ->
            emit(token)
        }
    } finally {
        currentGenerationId.compareAndSet(genId, null)
    }
}.flowOn(Dispatchers.Default)
```

**Files to Modify:**
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/EdgeVeda.kt`
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/Types.kt`
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/internal/NativeBridge.kt`
- `edge-veda/kotlin/src/main/cpp/edge_veda_jni.cpp`

**JNI Implementation (edge_veda_jni.cpp):**

```cpp
// Add to existing JNI methods
JNIEXPORT jobject JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_getModelInfo(JNIEnv* env, jobject /* this */) {
    // Get model info from C API
    ev_model_info info;
    int result = ev_get_model_info(g_context, &info);
    
    if (result != 0) {
        throwJavaException(env, "Failed to get model info");
        return nullptr;
    }
    
    // Create HashMap
    jclass hashMapClass = env->FindClass("java/util/HashMap");
    jmethodID initMethod = env->GetMethodID(hashMapClass, "<init>", "()V");
    jmethodID putMethod = env->GetMethodID(hashMapClass, "put",
        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    
    jobject hashMap = env->NewObject(hashMapClass, initMethod);
    
    // Add entries
    putStringEntry(env, hashMap, putMethod, "name", info.name);
    putStringEntry(env, hashMap, putMethod, "arch", info.architecture);
    putStringEntry(env, hashMap, putMethod, "n_params", std::to_string(info.n_params).c_str());
    putStringEntry(env, hashMap, putMethod, "n_ctx", std::to_string(info.n_ctx).c_str());
    putStringEntry(env, hashMap, putMethod, "n_vocab", std::to_string(info.n_vocab).c_str());
    putStringEntry(env, hashMap, putMethod, "quantization", info.quantization);
    
    return hashMap;
}

JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_resetContext(JNIEnv* env, jobject /* this */) {
    if (!g_context) {
        throwJavaException(env, "Context not initialized");
        return;
    }
    
    int result = ev_reset(g_context);
    if (result != 0) {
        throwJavaException(env, "Failed to reset context");
    }
}

JNIEXPORT void JNICALL
Java_com_edgeveda_sdk_internal_NativeBridge_cancelGeneration(
    JNIEnv* env, jobject /* this */, jstring genId) {
    
    const char* id = env->GetStringUTFChars(genId, nullptr);
    
    // Find and cancel the generation
    auto it = g_active_generations.find(id);
    if (it != g_active_generations.end()) {
        it->second.cancelled = true;
    }
    
    env->ReleaseStringUTFChars(genId, id);
}
```

**Success Criteria:**
- [ ] All 4 methods implemented and tested
- [ ] JNI bindings working correctly
- [ ] Unit tests passing
- [ ] Example app updated

---

### 1.2 Swift SDK Core APIs

**Status:** 🔄 In Progress

#### Missing Features

- [ ] `isModelLoaded()` - Check if model is loaded
- [ ] `cancelGeneration()` - Replace placeholder with real implementation

#### Implementation Details

**1.2.1 isModelLoaded() Implementation**

```swift
// In EdgeVeda.swift
public func isModelLoaded() -> Bool {
    return context != nil
}
```

**1.2.2 cancelGeneration() Implementation**

```swift
// In EdgeVeda.swift
private var currentGenerationTask: Task<Void, Error>?

public func cancelGeneration() async throws {
    guard context != nil else {
        throw EdgeVedaError.modelNotLoaded
    }
    
    currentGenerationTask?.cancel()
    currentGenerationTask = nil
}

// Update generateStream to track task
public func generateStream(_ prompt: String, options: GenerateOptions) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            guard let ctx = context else {
                continuation.finish(throwing: EdgeVedaError.modelNotLoaded)
                return
            }

            do {
                try await FFIBridge.generateStream(
                    ctx: ctx,
                    prompt: prompt,
                    maxTokens: options.maxTokens,
                    temperature: options.temperature,
                    topP: options.topP,
                    topK: options.topK,
                    repeatPenalty: options.repeatPenalty,
                    frequencyPenalty: 0.0,
                    presencePenalty: 0.0,
                    stopSequences: options.stopSequences
                ) { @Sendable token in
                    if Task.isCancelled {
                        return
                    }
                    continuation.yield(token)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        
        currentGenerationTask = task
        
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}
```

**Files to Modify:**
- `edge-veda/swift/Sources/EdgeVeda/EdgeVeda.swift`

**Success Criteria:**
- [ ] Both methods implemented and tested
- [ ] Cancellation properly interrupts generation
- [ ] Example app updated
- [ ] Documentation updated

---

### 1.3 React Native SDK Core APIs

**Status:** 🔄 In Progress

#### Missing Features

- [ ] `resetContext()` - Reset conversation context
- [ ] `isModelLoaded()` - Check if model is loaded (already exists, verify)

#### Implementation Details

**1.3.1 resetContext() Implementation**

```typescript
// In EdgeVeda.ts
async resetContext(): Promise<void> {
  try {
    if (!this.isModelLoaded()) {
      throw new EdgeVedaError(
        EdgeVedaErrorCode.MODEL_NOT_LOADED,
        'Model is not loaded'
      );
    }

    await NativeEdgeVeda.resetContext();
  } catch (error) {
    if (error instanceof EdgeVedaError) {
      throw error;
    }

    throw new EdgeVedaError(
      EdgeVedaErrorCode.UNKNOWN_ERROR,
      'Failed to reset context',
      error instanceof Error ? error.message : String(error)
    );
  }
}
```

**Native Module (iOS):**

```swift
// In EdgeVeda.swift
@objc
func resetContext() async throws {
    guard let edgeVeda = edgeVeda else {
        throw EdgeVedaError.modelNotLoaded
    }
    
    try await edgeVeda.resetContext()
}
```

**Native Module (Android):**

```kotlin
// In EdgeVedaModule.kt
@ReactMethod
fun resetContext(promise: Promise) {
    launch {
        try {
            edgeVeda?.resetContext()
            promise.resolve(null)
        } catch (e: Exception) {
            promise.reject("RESET_FAILED", e.message, e)
        }
    }
}
```

**Files to Modify:**
- `edge-veda/react-native/src/EdgeVeda.ts`
- `edge-veda/react-native/ios/EdgeVeda.swift`
- `edge-veda/react-native/android/src/main/java/com/edgeveda/EdgeVedaModule.kt`

**Success Criteria:**
- [ ] resetContext() implemented on both iOS and Android
- [ ] TypeScript bindings working
- [ ] Example app updated
- [ ] Tests passing

---

### 1.4 Web SDK Core APIs

**Status:** 🔄 In Progress

#### Missing Features

- [ ] `resetContext()` - Reset conversation context
- [ ] `isModelLoaded()` - Check if model is loaded (verify implementation)

#### Implementation Details

**1.4.1 resetContext() Implementation**

```typescript
// In index.ts
async resetContext(): Promise<void> {
  if (!this.initialized || !this.worker) {
    throw new Error('EdgeVeda not initialized. Call init() first.');
  }

  await this.sendWorkerMessage({
    type: 'reset_context' as WorkerMessageType.RESET_CONTEXT,
  });
}
```

**Add to types.ts:**

```typescript
export enum WorkerMessageType {
  // ... existing types
  RESET_CONTEXT = 'reset_context',
  RESET_SUCCESS = 'reset_success',
}

export interface ResetContextMessage extends WorkerMessage {
  type: WorkerMessageType.RESET_CONTEXT;
}

export interface ResetSuccessMessage extends WorkerMessage {
  type: WorkerMessageType.RESET_SUCCESS;
}
```

**Worker Handler (worker.ts):**

```typescript
case 'reset_context':
  if (model) {
    model.resetContext();
    self.postMessage({
      type: 'reset_success',
      id: message.id,
    });
  } else {
    self.postMessage({
      type: 'error',
      id: message.id,
      error: 'Model not loaded',
    });
  }
  break;
```

**1.4.2 isModelLoaded() Verification**

Already exists in index.ts as `isInitialized()` - just verify functionality.

**Files to Modify:**
- `edge-veda/web/src/index.ts`
- `edge-veda/web/src/types.ts`
- `edge-veda/web/src/worker.ts`

**Success Criteria:**
- [ ] resetContext() implemented
- [ ] Worker message handling complete
- [ ] Example updated
- [ ] Tests passing

---

## Phase 1 Summary

### Timeline & Milestones

**Week 1:**
- ✅ Documentation complete (SDK_FEATURE_PARITY_ANALYSIS.md, IMPLEMENTATION_ROADMAP.md)
- 🔄 Kotlin SDK: getModelInfo(), resetContext(), isModelLoaded()
- 🔄 Swift SDK: isModelLoaded()

**Week 2:**
- 🔄 Kotlin SDK: cancelGeneration() with JNI
- 🔄 Swift SDK: cancelGeneration() with Task tracking
- 🔄 React Native: resetContext() for iOS and Android
- 🔄 Web SDK: resetContext() with worker messages

### Success Criteria

- [ ] All platforms have 100% Tier 1 API coverage (10/10)
- [ ] All placeholder implementations replaced
- [ ] Example apps updated for each platform
- [ ] Documentation updated
- [ ] Tests passing (≥80% coverage)

---

## Phase 2: ChatSession Implementation ✅ COMPLETED

**Timeline:** 3-4 weeks (Completed ahead of schedule)
**Priority:** 🟡 **MEDIUM**  
**Completion Date:** November 2, 2026

### Overview

Implement multi-turn conversation management across all platforms, enabling:
- Conversation history tracking
- Context window management
- Auto-summarization at overflow
- System prompt presets
- Chat template formatting

### 2.1 Architecture Design

**Core Components:**

1. **ChatSession Class** - Main conversation manager
2. **ChatMessage** - Individual message with role and content
3. **ChatTemplate** - Format conversations for specific models
4. **SystemPromptPreset** - Pre-configured system prompts

**Shared Logic:**
- Extract conversation logic from Flutter ChatSession
- Design platform-agnostic conversation state machine
- Define common message format and serialization

### 2.2 Swift ChatSession Implementation

**Priority:** First (iOS primary target)

```swift
// Sources/EdgeVeda/ChatSession.swift
@available(iOS 15.0, macOS 12.0, *)
public actor ChatSession {
    private let edgeVeda: EdgeVeda
    private var messages: [ChatMessage] = []
    private let maxContextLength: Int
    private let systemPrompt: String?
    
    public init(
        edgeVeda: EdgeVeda,
        systemPrompt: SystemPromptPreset = .assistant,
        maxContextLength: Int = 2048
    ) {
        self.edgeVeda = edgeVeda
        self.systemPrompt = systemPrompt.text
        self.maxContextLength = maxContextLength
        
        if let prompt = self.systemPrompt {
            messages.append(ChatMessage(role: .system, content: prompt))
        }
    }
    
    public func send(_ message: String) async throws -> String {
        messages.append(ChatMessage(role: .user, content: message))
        
        let prompt = formatPrompt()
        let response = try await edgeVeda.generate(prompt)
        
        messages.append(ChatMessage(role: .assistant, content: response))
        
        return response
    }
    
    public func sendStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                messages.append(ChatMessage(role: .user, content: message))
                
                let prompt = formatPrompt()
                var fullResponse = ""
                
                do {
                    for try await token in edgeVeda.generateStream(prompt) {
                        fullResponse += token
                        continuation.yield(token)
                    }
                    
                    messages.append(ChatMessage(role: .assistant, content: fullResponse))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func reset() async throws {
        messages.removeAll()
        if let prompt = systemPrompt {
            messages.append(ChatMessage(role: .system, content: prompt))
        }
        try await edgeVeda.resetContext()
    }
    
    private func formatPrompt() -> String {
        // Use chat template to format messages
        return ChatTemplate.llama3.format(messages: messages)
    }
    
    public var turnCount: Int {
        messages.filter { $0.role == .user }.count
    }
    
    public var contextUsage: Double {
        let totalTokens = estimateTokens()
        return Double(totalTokens) / Double(maxContextLength)
    }
    
    private func estimateTokens() -> Int {
        // Rough estimate: 1 token ≈ 4 characters
        let totalChars = messages.reduce(0) { $0 + $1.content.count }
        return totalChars / 4
    }
}

public struct ChatMessage: Sendable {
    public let role: ChatRole
    public let content: String
    public let timestamp: Date
    
    public init(role: ChatRole, content: String, timestamp: Date = Date()) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum ChatRole: String, Sendable {
    case system
    case user
    case assistant
}

public enum SystemPromptPreset {
    case assistant
    case coder
    case concise
    case creative
    
    var text: String {
        switch self {
        case .assistant:
            return "You are a helpful AI assistant."
        case .coder:
            return "You are an expert programmer. Provide clear, concise code examples."
        case .concise:
            return "You are a concise assistant. Keep responses brief and to the point."
        case .creative:
            return "You are a creative AI with vivid imagination. Be expressive and original."
        }
    }
}

public enum ChatTemplate {
    case llama3
    case chatml
    case mistral
    
    func format(messages: [ChatMessage]) -> String {
        switch self {
        case .llama3:
            return formatLlama3(messages: messages)
        case .chatml:
            return formatChatML(messages: messages)
        case .mistral:
            return formatMistral(messages: messages)
        }
    }
    
    private func formatLlama3(messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            prompt += "<|start_header_id|>\(msg.role.rawValue)<|end_header_id|>\n\n"
            prompt += "\(msg.content)<|eot_id|>"
        }
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return prompt
    }
    
    private func formatChatML(messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            prompt += "<|im_start|>\(msg.role.rawValue)\n\(msg.content)<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n"
        return prompt
    }
    
    private func formatMistral(messages: [ChatMessage]) -> String {
        var prompt = ""
        for msg in messages {
            if msg.role == .user {
                prompt += "[INST] \(msg.content) [/INST]"
            } else if msg.role == .assistant {
                prompt += " \(msg.content)</s>"
            }
        }
        return prompt
    }
}
```

**Files to Create:**
- `edge-veda/swift/Sources/EdgeVeda/ChatSession.swift`
- `edge-veda/swift/Sources/EdgeVeda/ChatTypes.swift`
- `edge-veda/swift/Sources/EdgeVeda/ChatTemplate.swift`

**Estimated Effort:** 1 week

### 2.3 Kotlin ChatSession Implementation

Similar architecture adapted for Kotlin coroutines and Flow:

```kotlin
class ChatSession(
    private val edgeVeda: EdgeVeda,
    private val systemPrompt: SystemPromptPreset = SystemPromptPreset.ASSISTANT,
    private val maxContextLength: Int = 2048
) {
    private val messages = mutableListOf<ChatMessage>()
    
    init {
        systemPrompt.text?.let {
            messages.add(ChatMessage(ChatRole.SYSTEM, it))
        }
    }
    
    suspend fun send(message: String): String {
        messages.add(ChatMessage(ChatRole.USER, message))
        
        val prompt = formatPrompt()
        val response = edgeVeda.generate(prompt)
        
        messages.add(ChatMessage(ChatRole.ASSISTANT, response))
        
        return response
    }
    
    fun sendStream(message: String): Flow<String> = flow {
        messages.add(ChatMessage(ChatRole.USER, message))
        
        val prompt = formatPrompt()
        val fullResponse = StringBuilder()
        
        edgeVeda.generateStream(prompt).collect { token ->
            fullResponse.append(token)
            emit(token)
        }
        
        messages.add(ChatMessage(ChatRole.ASSISTANT, fullResponse.toString()))
    }
    
    suspend fun reset() {
        messages.clear()
        systemPrompt.text?.let {
            messages.add(ChatMessage(ChatRole.SYSTEM, it))
        }
        edgeVeda.resetContext()
    }
    
    val turnCount: Int
        get() = messages.count { it.role == ChatRole.USER }
    
    val contextUsage: Double
        get() {
            val totalTokens = estimateTokens()
            return totalTokens.toDouble() / maxContextLength.toDouble()
        }
    
    private fun formatPrompt(): String {
        return ChatTemplate.LLAMA3.format(messages)
    }
    
    private fun estimateTokens(): Int {
        val totalChars = messages.sumOf { it.content.length }
        return totalChars / 4
    }
}
```

**Files to Create:**
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/ChatSession.kt`
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/ChatTypes.kt`
- `edge-veda/kotlin/src/main/kotlin/com/edgeveda/sdk/ChatTemplate.kt`

**Estimated Effort:** 1 week

### 2.4 React Native ChatSession

TypeScript implementation using the existing EdgeVeda instance:

```typescript
export class ChatSession {
  private edgeVeda: EdgeVedaSDK;
  private messages: ChatMessage[] = [];
  private maxContextLength: number;
  
  constructor(
    edgeVeda: EdgeVedaSDK,
    options: {
      systemPrompt?: SystemPromptPreset;
      maxContextLength?: number;
    } = {}
  ) {
    this.edgeVeda = edgeVeda;
    this.maxContextLength = options.maxContextLength ?? 2048;
    
    if (options.systemPrompt) {
      this.messages.push({
        role: ChatRole.SYSTEM,
        content: getSystemPrompt(options.systemPrompt),
        timestamp: new Date(),
      });
    }
  }
  
  async send(message: string): Promise<string> {
    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });
    
    const prompt = this.formatPrompt();
    const response = await this.edgeVeda.generate(prompt);
    
    this.messages.push({
      role: ChatRole.ASSISTANT,
      content: response,
      timestamp: new Date(),
    });
    
    return response;
  }
  
  async sendStream(
    message: string,
    onToken: TokenCallback
  ): Promise<void> {
    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });
    
    const prompt = this.formatPrompt();
    let fullResponse = '';
    
    await this.edgeVeda.generateStream(prompt, (token, done) => {
      fullResponse += token;
      onToken(token, done);
      
      if (done) {
        this.messages.push({
          role: ChatRole.ASSISTANT,
          content: fullResponse,
          timestamp: new Date(),
        });
      }
    });
  }
  
  async reset(): Promise<void> {
    const systemMsg = this.messages.find(m => m.role === ChatRole.SYSTEM);
    this.messages = systemMsg ? [systemMsg] : [];
    await this.edgeVeda.resetContext();
  }
  
  get turnCount(): number {
    return this.messages.filter(m => m.role === ChatRole.USER).length;
  }
  
  get contextUsage(): number {
    const totalTokens = this.estimateTokens();
    return totalTokens / this.maxContextLength;
  }
  
  private formatPrompt(): string {
    return formatLlama3(this.messages);
  }
  
  private estimateTokens(): number {
    const totalChars = this.messages.reduce((sum, msg) => sum + msg.content.length, 0);
    return Math.floor(totalChars / 4);
  }
}
```

**Files to Create:**
- `edge-veda/react-native/src/ChatSession.ts`
- `edge-veda/react-native/src/ChatTypes.ts`
- `edge-veda/react-native/src/ChatTemplate.ts`

**Estimated Effort:** 1 week

### 2.5 Web ChatSession

Similar to React Native but adapted for Web environment:

```typescript
export class ChatSession {
  private edgeVeda: EdgeVeda;
  private messages: ChatMessage[] = [];
  private maxContextLength: number;
  
  constructor(
    edgeVeda: EdgeVeda,
    options: {
      systemPrompt?: SystemPromptPreset;
      maxContextLength?: number;
    } = {}
  ) {
    // Similar implementation to React Native
  }
  
  async send(message: string): Promise<string> {
    // Similar implementation
  }
  
  async *sendStream(message: string): AsyncGenerator<string, void, unknown> {
    this.messages.push({
      role: ChatRole.USER,
      content: message,
      timestamp: new Date(),
    });
    
    const prompt = this.formatPrompt();
    let fullResponse = '';
    
    for await (const token of this.edgeVeda.generateStream({ prompt })) {
      fullResponse += token.text;
      yield token.text;
    }
    
    this.messages.push({
      role: ChatRole.ASSISTANT,
      content: fullResponse,
      timestamp: new Date(),
    });
  }
  
  async reset(): Promise<void> {
    const systemMsg = this.messages.find(m => m.role === ChatRole.SYSTEM);
    this.messages = systemMsg ? [systemMsg] : [];
    await this.edgeVeda.resetContext();
  }
  
  // ... rest similar to React Native
}
```

**Files to Create:**
- `edge-veda/web/src/ChatSession.ts`
- `edge-veda/web/src/ChatTypes.ts`
- `edge-veda/web/src/ChatTemplate.ts`

**Estimated Effort:** 1 week

### Phase 2 Summary

**Total Timeline:** Completed  
**Platforms:** Swift → Kotlin → React Native → Web (All Complete)

**Success Criteria:**
- [x] ChatSession implemented on all 4 non-Flutter platforms
- [x] System prompt presets available (assistant, coder, concise, creative)
- [x] Chat templates (Llama3, ChatML, Mistral) with proper formatting
- [x] Context management working (token estimation, context usage tracking)
- [x] ChatSession exported from main SDK entry points
- [ ] Example apps demonstrate conversations (pending)
- [ ] Documentation complete (pending)
- [ ] Tests passing (≥80% coverage) (pending)

**Implementation Highlights:**
- **Swift**: Actor-based ChatSession with async/await, proper actor isolation
- **Kotlin**: Coroutines-based with Flow for streaming, synchronized message history
- **React Native**: TypeScript implementation with EdgeVeda singleton integration
- **Web**: Browser-optimized with AsyncGenerator for streaming

**Files Created:**
- Swift: ChatTypes.swift, ChatTemplate.swift, ChatSession.swift
- Kotlin: ChatTypes.kt, ChatTemplate.kt, ChatSession.kt
- React Native: ChatTypes.ts, ChatTemplate.ts, ChatSession.ts
- Web: ChatTypes.ts, ChatTemplate.ts, ChatSession.ts

**Next Steps:**
- Update example applications to demonstrate ChatSession usage
- Add comprehensive documentation with usage examples
- Implement unit and integration tests for ChatSession

---

## Phase 3: Vision Inference (FUTURE)

**Timeline:** 4-6 weeks  
**Priority:** 🟢 **LOW-MEDIUM**  
**Start Date:** TBD (after Phase 2)

### Overview

Port VisionWorker and vision inference capabilities to enable:
- VLM model loading
- Image description
- Continuous vision processing
- Frame queue with backpressure

### 3.1 Swift Vision Implementation

**Priority:** First (iOS camera use cases)

**Approach:**
1. Port VisionWorker isolate pattern to Swift actor
2. Implement vision FFI bridge
3. Add camera utilities
4. Implement frame queue

**Estimated Effort:** 2 weeks

### 3.2 React Native Vision

Cross-platform camera integration with native modules.

**Estimated Effort:** 2 weeks

### 3.3 Kotlin Vision

Android camera integration with JNI bridge.

**Estimated Effort:** 2 weeks

### 3.4 Web Vision (Optional)

WebRTC/MediaStream integration for browser cameras.

**Estimated Effort:** 2 weeks (if pursued)

---

## Phase 4: Runtime Supervision (LONG-TERM)

**Timeline:** 8-12 weeks  
**Priority:** 🔵 **LOW** (Advanced)  
**Start Date:** TBD

### Features

- Compute budgets
- Scheduler
- Runtime policy
- Telemetry
- Performance tracing

This phase requires significant architectural work and platform-specific OS integration. Will be
