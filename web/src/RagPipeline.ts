/**
 * End-to-end RAG (Retrieval-Augmented Generation) pipeline for on-device use.
 * 
 * Combines text embeddings, vector search, and LLM generation into a single
 * pipeline that retrieves relevant context before generating responses.
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
 * const response = await rag.query('What is TypeScript?');
 * console.log(response.text); // Uses retrieved context
 * ```
 */

import { VectorIndex, SearchResult } from './VectorIndex';
import { 
  GenerateResult, 
  StreamChunk, 
  GenerateOptions, 
  CancelToken,
  EmbeddingResult 
} from './types';

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
   * Template for injecting retrieved context into the prompt
   * Use {context} for retrieved text and {query} for the user query
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
  promptTemplate: 'Use the following context to answer the question.\n\nContext:\n{context}\n\nQuestion: {query}\n\nAnswer:',
  maxContextLength: 2000,
};

/**
 * Interface representing the EdgeVeda instance for type safety.
 * 
 * This is a minimal interface that RagPipeline needs. The actual EdgeVeda
 * class should implement these methods.
 */
export interface IEdgeVeda {
  /**
   * Generate embeddings for text
   */
  embed(text: string): Promise<EmbeddingResult>;

  /**
   * Generate text completion
   */
  generate(
    prompt: string,
    options?: GenerateOptions
  ): Promise<GenerateResult>;

  /**
   * Generate text with streaming
   */
  generateStream(
    prompt: string,
    options?: GenerateOptions,
    cancelToken?: CancelToken
  ): AsyncGenerator<StreamChunk, void, unknown>;
}

/**
 * End-to-end RAG pipeline: embed query -> search index -> inject context -> generate
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

  /**
   * The underlying vector index
   */
  get index(): VectorIndex {
    return this._index;
  }

  /**
   * Current RAG configuration
   */
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
    this._index.add(
      id,
      result.embeddings,
      {
        text,
        ...metadata,
      }
    );
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
   *   'doc3': 'Third document text...',
   * });
   * ```
   */
  async addDocuments(documents: Record<string, string>): Promise<void> {
    for (const [id, text] of Object.entries(documents)) {
      await this.addDocument(id, text);
    }
  }

  /**
   * Query with RAG: embed query -> retrieve context -> generate response
   * 
   * Returns a GenerateResult with the LLM's answer augmented by
   * retrieved context from the vector index.
   * 
   * @param queryText - User's query text
   * @param options - Optional generation parameters
   * 
   * @example
   * ```typescript
   * const response = await rag.query('What is TypeScript?', {
   *   maxTokens: 256,
   *   temperature: 0.7,
   * });
   * console.log(response.text);
   * ```
   */
  async query(
    queryText: string,
    options?: GenerateOptions
  ): Promise<GenerateResult> {
    // Step 1: Embed the query
    const queryEmbedding = await this._embedder.embed(queryText);

    // Step 2: Search the vector index
    const results = this._index.query(
      queryEmbedding.embeddings,
      this._config.topK
    );

    // Step 3: Filter by minimum score and build context
    const relevantDocs = results.filter(
      (r) => r.score >= this._config.minScore
    );

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
    const augmentedPrompt = this._config.promptTemplate
      .replace('{context}', context)
      .replace('{query}', queryText);

    // Step 5: Generate response
    const response = await this._generator.generate(
      augmentedPrompt,
      options
    );

    return response;
  }

  /**
   * Query with RAG and streaming response
   * 
   * @param queryText - User's query text
   * @param options - Optional generation parameters
   * @param cancelToken - Optional cancellation token
   * 
   * @example
   * ```typescript
   * for await (const chunk of rag.queryStream('What is TypeScript?')) {
   *   process.stdout.write(chunk.token);
   *   if (chunk.done) {
   *     console.log('\nDone!');
   *   }
   * }
   * ```
   */
  async *queryStream(
    queryText: string,
    options?: GenerateOptions,
    cancelToken?: CancelToken
  ): AsyncGenerator<StreamChunk, void, unknown> {
    // Step 1: Embed the query
    const queryEmbedding = await this._embedder.embed(queryText);

    // Step 2: Search the vector index
    const results = this._index.query(
      queryEmbedding.embeddings,
      this._config.topK
    );

    // Step 3: Build context
    const contextParts: string[] = [];
    let totalLength = 0;
    const matchedDocs = results.filter(
      (r) => r.score >= this._config.minScore
    );
    for (const doc of matchedDocs) {
      const text = (doc.metadata['text'] as string) ?? '';
      if (totalLength + text.length > this._config.maxContextLength) break;
      contextParts.push(text);
      totalLength += text.length;
    }

    const context = contextParts.join('\n\n');

    // Step 4: Build augmented prompt
    const augmentedPrompt = this._config.promptTemplate
      .replace('{context}', context)
      .replace('{query}', queryText);

    // Step 5: Stream response
    yield* this._generator.generateStream(
      augmentedPrompt,
      options,
      cancelToken
    );
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
   *   console.log(result.metadata.text);
   * }
   * ```
   */
  async retrieve(
    queryText: string,
    k?: number
  ): Promise<SearchResult[]> {
    const queryEmbedding = await this._embedder.embed(queryText);
    return this._index.query(
      queryEmbedding.embeddings,
      k ?? this._config.topK
    );
  }

  /**
   * Get the number of documents in the index
   */
  get documentCount(): number {
    return this._index.size;
  }

  /**
   * Check if the index is empty
   */
  get isEmpty(): boolean {
    return this._index.isEmpty;
  }

  /**
   * Clear all documents from the index
   */
  clear(): void {
    this._index.clear();
  }

  /**
   * Delete a document by ID
   * 
   * @param id - Document ID to delete
   * @returns true if document was found and deleted, false otherwise
   */
  deleteDocument(id: string): boolean {
    return this._index.delete(id);
  }

  /**
   * Get metadata for a specific document
   * 
   * @param id - Document ID
   * @returns metadata object or null if not found
   */
  getDocumentMetadata(id: string): Record<string, any> | null {
    return this._index.getMetadata(id);
  }

  /**
   * Check if a document exists in the index
   * 
   * @param id - Document ID
   */
  hasDocument(id: string): boolean {
    return this._index.has(id);
  }

  /**
   * Get all document IDs in the index
   */
  get documentIds(): string[] {
    return this._index.ids;
  }

  /**
   * Save the index to a JSON-serializable object
   * 
   * The returned object can be serialized with JSON.stringify() and
   * later restored by creating a new VectorIndex with VectorIndex.load()
   * and then creating a new RagPipeline with that index.
   */
  saveIndex(): any {
    return this._index.save();
  }

  /**
   * Create a human-readable summary of the pipeline state
   */
  toString(): string {
    return `RagPipeline(documents: ${this.documentCount}, topK: ${this._config.topK}, minScore: ${this._config.minScore})`;
  }
}