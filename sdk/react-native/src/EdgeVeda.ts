import NativeEdgeVeda from './NativeEdgeVeda';
import type {
  EdgeVedaConfig,
  GenerateOptions,
  GenerateResponse,
  TokenEvent,
  TranscribeOptions,
  TranscriptionResult,
  EmbeddingResult,
  MemoryStats,
} from './types';

/**
 * Edge Veda React Native SDK — on-device AI inference.
 *
 * ```typescript
 * const model = await EdgeVeda.loadModel({ modelPath: 'path/to/model.gguf' });
 *
 * // Single-shot
 * const response = await model.generate('What is AI?');
 * console.log(response.text);
 *
 * // Streaming
 * model.generateStream('Explain quantum computing', {
 *   onToken: (event) => process.stdout.write(event.token),
 *   onComplete: (response) => console.log('Done:', response.text),
 * });
 *
 * model.dispose();
 * ```
 */
export class EdgeVeda {
  private handle: number;
  private disposed = false;

  private constructor(handle: number) {
    this.handle = handle;
  }

  /**
   * Load a model and create an EdgeVeda instance.
   */
  static async loadModel(config: EdgeVedaConfig): Promise<EdgeVeda> {
    const handle = await NativeEdgeVeda.initialize({
      modelPath: config.modelPath,
      maxTokens: config.maxTokens ?? 512,
      numThreads: config.numThreads ?? 4,
      gpuLayers: config.gpuLayers ?? -1,
      contextSize: config.contextSize ?? 2048,
      useGpu: config.useGpu ?? true,
      maxMemoryMb: config.maxMemoryMb ?? 1536,
    });
    return new EdgeVeda(handle);
  }

  private requireHandle(): number {
    if (this.disposed) {
      throw new Error('EdgeVeda instance has been disposed');
    }
    return this.handle;
  }

  /**
   * Generate a complete response.
   */
  async generate(
    prompt: string,
    options?: GenerateOptions
  ): Promise<GenerateResponse> {
    const handle = this.requireHandle();
    const result = (await NativeEdgeVeda.generate(
      handle,
      prompt,
      options ?? {}
    )) as GenerateResponse;
    return result;
  }

  /**
   * Stream tokens with callbacks.
   * Returns a cancel function.
   */
  generateStream(
    prompt: string,
    options?: GenerateOptions & {
      onToken?: (event: TokenEvent) => void;
      onComplete?: (response: GenerateResponse) => void;
      onError?: (error: Error) => void;
    }
  ): { cancel: () => void } {
    const handle = this.requireHandle();
    let streamHandle: number | null = null;
    let cancelled = false;

    const run = async () => {
      try {
        streamHandle = await NativeEdgeVeda.startStream(
          handle,
          prompt,
          options ?? {}
        );

        let text = '';
        let index = 0;
        const startTime = Date.now();

        while (!cancelled) {
          const tokenObj = await NativeEdgeVeda.nextToken(streamHandle);
          if (tokenObj === null) break;

          const token = (tokenObj as any).token as string;
          text += token;
          index++;

          options?.onToken?.({
            token,
            index,
            isFinal: false,
          });
        }

        const latencyMs = Date.now() - startTime;
        options?.onComplete?.({
          text,
          promptTokens: 0,
          completionTokens: index,
          totalTokens: index,
          latencyMs,
          tokensPerSecond: latencyMs > 0 ? (index / latencyMs) * 1000 : null,
        });
      } catch (error) {
        options?.onError?.(
          error instanceof Error ? error : new Error(String(error))
        );
      }
    };

    run();

    return {
      cancel: () => {
        cancelled = true;
        if (streamHandle !== null) {
          NativeEdgeVeda.cancelStream(streamHandle);
        }
      },
    };
  }

  /**
   * Transcribe audio to text.
   */
  async transcribe(options: TranscribeOptions): Promise<TranscriptionResult> {
    const handle = this.requireHandle();
    const result = (await NativeEdgeVeda.transcribe(
      handle,
      options.audioPath,
      options
    )) as TranscriptionResult;
    return result;
  }

  /**
   * Compute text embeddings.
   */
  async embed(text: string): Promise<EmbeddingResult> {
    const handle = this.requireHandle();
    const result = (await NativeEdgeVeda.embed(
      handle,
      text
    )) as EmbeddingResult;
    return result;
  }

  /**
   * Get memory usage statistics.
   */
  async getMemoryUsage(): Promise<MemoryStats> {
    const handle = this.requireHandle();
    return (await NativeEdgeVeda.getMemoryUsage(handle)) as MemoryStats;
  }

  /**
   * Release native resources.
   */
  dispose(): void {
    if (!this.disposed) {
      NativeEdgeVeda.dispose(this.handle);
      this.disposed = true;
    }
  }
}
