/**
 * End-to-end RAG (Retrieval-Augmented Generation) pipeline for on-device use.
 *
 * Combines text embeddings, vector search, and LLM generation into a single
 * pipeline that retrieves relevant context before generating responses.
 *
 * Adapted from the web SDK for React Native's TurboModule bridge:
 * - `generate()` returns `Promise<string>` (raw text) rather than GenerateResult
 * - `generateStream()` uses a callback pattern rather than async generator
 *
 * @example
 * ```typescript
 * const rag = new RagPipeline({
 *   edgeVeda: edgeVeda,
 *   index: vectorIndex,
 * });
 *
 * // Add documents
 * await rag.addDocument('doc1', 'TypeScript is a typed superset of JavaScript...');
 *
 * // Query with RAG
 * const answer = await rag.query('What is TypeScript?');
 * console.log(answer);
 * ```
 */

import { VectorIndex, SearchResult } from './VectorIndex';
import type { GenerateOptions, CancelToken, EmbeddingResult } from './types';

/**
 * Configuration for the RAG pipeline
 */
export interface RagConfig {
  /**
   * Number of documents to retrieve for context
   * @default 3
   */
  topK?: number;

  /**
   * Minimum similarity score to include a document (0.0-1.0)
   * @default 0.0
   */
  minScore?: number;

  /**
   * Template for injecting retrieved context into the prompt.
   * Use {context} for retrieved text and {query} for the user query.
   * @default 'Use the following context to answer the question.\n\nContext:\n{context}\n\nQuestion: {query}\n\nAnswer:'
   */
  promptTemplate?: string;

  /**
   * Maximum context length in characters (to prevent overflow)
   * @default 2000
   */
  maxContextLength?: number;
}

/**
 * Default RAG configuration
 */
const DEFAULT_RAG_CONFIG: Required<RagConfig> = {
  topK: 3,
  minScore: 0.0,
  promptTemplate:
    'Use the following context to answer the question.\n\nContext:\n{context}\n\nQuestion: {query}\n\nAnswer:',
  maxContextLength: 2000,
};

/**
 * Minimal EdgeVeda interface required by RagPipeline.
 *
 * The EdgeVedaSDK class satisfies this interface. Providing an interface
 * here keeps RagPipeline testable without a full SDK instance.
 */
export interface IEdgeVeda {
  /** Generate embeddings for text */
  embed(text: string): Promise<EmbeddingResult>;

  /** Generate text completion */
  generate(prompt: string, options?: GenerateOptions): Promise<string>;

  /** Generate text with streaming tokens via callback */
  generateStream(
    prompt: string,
    onToken: (token: string, done: boolean) => void,
    options?: GenerateOptions
  ): Promise<void>;
}

/**
 * End-to-end RAG pipeline: embed query → search index → inject context → generate
 */
export class RagPipeline {
  private readonly _embedder: IEdgeVeda;
  private readonly _generator: IEdgeVeda;
  private readonly _index: VectorIndex;
  private readonly _config: Required<RagConfig>;

  /**
   * Create a RAG pipeline with a single EdgeVeda instance for both embedding
   * and generation. Suitable when one model handles both tasks.
   */
  constructor(config: {
    edgeVeda: IEdgeVeda;
    index: VectorIndex;
    config?: RagConfig;
  }) {
    this._embedder = config.edgeVeda;
    this._generator = config.edgeVeda;
    this._index = config.index;
    this._config = { ...DEFAULT_RAG_CONFIG, ...config.config };
  }

  /**
   * Create a RAG pipeline with separate embedding and generation models.
   *
   * Use this when your embedding model (e.g., all-MiniLM-L6-v2) is different
   * from your generation model (e.g., Llama 3.2 1B). This is the recommended
   * configuration for production RAG.
   *
   * @example
   * ```typescript
   * const rag = RagPipeline.withModels({
   *   embedder: embeddingModel,
   *   generator: llmModel,
   *   index: vectorIndex,
   * });
   * ```
   */
  static withModels(config: {
    embedder: IEdgeVeda;
    generator: IEdgeVeda;
    index: VectorIndex;
    config?: RagConfig;
  }): RagPipeline {
    const instance = Object.create(RagPipeline.prototype);
    instance._embedder = config.embedder;
    instance._generator = config.generator;
    instance._index = config.index;
    instance._config = { ...DEFAULT_RAG_CONFIG, ...config.config };
    return instance;
  }

  /** The underlying vector index */
  get index(): VectorIndex {
    return this._index;
  }

  /** Current RAG configuration */
  get config(): Required<RagConfig> {
    return { ...this._config };
  }

  /**
   * Add a document to the index
   *
   * Embeds the text and stores it in the vector index with the given ID.
   * Optional metadata is stored alongside the vector for retrieval.
   *
   * @param id - Unique document identifier
   * @param text - Document text to embed and store
   * @param metadata - Optional metadata to attach to the document
   *
   * @example
   * ```typescript
   * await rag.addDocument(
   *   'doc1',
   *   'TypeScript adds static typing to JavaScript.',
   *   { source: 'typescript-handbook.pdf', page: 1 }
   * );
   * ```
   */
  async addDocument(
    id: string,
    text: string,
    metadata?: Record<string, any>
  ): Promise<void> {
    const result = await this._embedder.embed(text);
    this._index.add(id, result.embedding, { text, ...metadata });
  }

  /**
   * Add multiple documents in batch
   *
   * @param documents - Map of document ID to document text
   *
   * @example
   * ```typescript
   * await rag.addDocuments({
   *   'doc1': 'First document text...',
   *   'doc2': 'Second document text...',
   * });
   * ```
   */
  async addDocuments(documents: Record<string, string>): Promise<void> {
    for (const [id, text] of Object.entries(documents)) {
      await this.addDocument(id, text);
    }
  }

  /**
   * Query with RAG: embed query → retrieve context → generate response
   *
   * Returns the LLM's answer augmented by retrieved context from the
   * vector index.
   *
   * @param queryText - User's query text
   * @param options - Optional generation parameters
   *
   * @example
   * ```typescript
   * const answer = await rag.query('What is TypeScript?', {
   *   maxTokens: 256,
   *   temperature: 0.7,
   * });
   * console.log(answer);
   * ```
   */
  async query(
    queryText: string,
    options?: GenerateOptions
  ): Promise<string> {
    const augmentedPrompt = await this._buildPrompt(queryText);
    return this._generator.generate(augmentedPrompt, options);
  }

  /**
   * Query with RAG and streaming response
   *
   * @param queryText - User's query text
   * @param onToken - Callback invoked for each generated token
   * @param options - Optional generation parameters
   * @param _cancelToken - Reserved for future cancellation support
   *
   * @example
   * ```typescript
   * await rag.queryStream('What is TypeScript?', (token, done) => {
   *   process.stdout.write(token);
   *   if (done) console.log('\nDone!');
   * });
   * ```
   */
  async queryStream(
    queryText: string,
    onToken: (token: string, done: boolean) => void,
    options?: GenerateOptions,
    _cancelToken?: CancelToken
  ): Promise<void> {
    const augmentedPrompt = await this._buildPrompt(queryText);
    await this._generator.generateStream(augmentedPrompt, onToken, options);
  }

  /**
   * Retrieve similar documents without generating (useful for debugging)
   *
   * Returns search results without calling the LLM. Useful for testing
   * the retrieval part of the pipeline or debugging context selection.
   *
   * @param queryText - Query text to search for
   * @param k - Number of documents to retrieve (defaults to config.topK)
   *
   * @example
   * ```typescript
   * const results = await rag.retrieve('What is TypeScript?', 5);
   * for (const result of results) {
   *   console.log(`${result.id}: ${result.score.toFixed(3)}`);
   * }
   * ```
   */
  async retrieve(queryText: string, k?: number): Promise<SearchResult[]> {
    const queryEmbedding = await this._embedder.embed(queryText);
    return this._index.query(queryEmbedding.embedding, k ?? this._config.topK);
  }

  /** Number of documents in the index */
  get documentCount(): number {
    return this._index.size;
  }

  /** Whether the index is empty */
  get isEmpty(): boolean {
    return this._index.isEmpty;
  }

  /** Clear all documents from the index */
  clear(): void {
    this._index.clear();
  }

  /**
   * Delete a document by ID
   *
   * @returns true if document was found and deleted, false otherwise
   */
  deleteDocument(id: string): boolean {
    return this._index.delete(id);
  }

  /**
   * Get metadata for a specific document
   *
   * @returns metadata object or null if not found
   */
  getDocumentMetadata(id: string): Record<string, any> | null {
    return this._index.getMetadata(id);
  }

  /** Check if a document exists in the index */
  hasDocument(id: string): boolean {
    return this._index.has(id);
  }

  /** All document IDs in the index */
  get documentIds(): string[] {
    return this._index.ids;
  }

  /**
   * Save the index to a JSON-serializable object
   *
   * The returned object can be serialized with JSON.stringify() and later
   * restored by creating a new VectorIndex with VectorIndex.load().
   */
  saveIndex(): any {
    return this._index.save();
  }

  toString(): string {
    return `RagPipeline(documents: ${this.documentCount}, topK: ${this._config.topK}, minScore: ${this._config.minScore})`;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  private async _buildPrompt(queryText: string): Promise<string> {
    // Step 1: Embed the query
    const queryEmbedding = await this._embedder.embed(queryText);

    // Step 2: Search the vector index
    const results = this._index.query(queryEmbedding.embedding, this._config.topK);

    // Step 3: Filter by minimum score and build context
    const relevantDocs = results.filter((r) => r.score >= this._config.minScore);

    const contextParts: string[] = [];
    let totalLength = 0;
    for (const doc of relevantDocs) {
      const text = (doc.metadata['text'] as string) ?? '';
      if (totalLength + text.length > this._config.maxContextLength) break;
      contextParts.push(text);
      totalLength += text.length;
    }

    const context = contextParts.join('\n\n');

    // Step 4: Build augmented prompt
    return this._config.promptTemplate
      .replace('{context}', context)
      .replace('{query}', queryText);
  }
}
