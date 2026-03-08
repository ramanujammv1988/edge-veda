/**
 * Pure TypeScript vector index for on-device RAG using cosine similarity.
 *
 * Stores document embeddings and retrieves the k most similar documents
 * for a given query embedding. Uses cosine distance (optimal for L2-normalized
 * embeddings from ev_embed).
 *
 * Implementation Note: This uses brute-force linear search for simplicity
 * and portability (O(n) query time). For large indices (>10k vectors),
 * consider using approximate nearest neighbor algorithms like HNSW.
 *
 * @example
 * ```typescript
 * const index = new VectorIndex({ dimensions: 384 });
 * index.add('doc1', [0.1, 0.2, ...], { title: 'Hello' });
 * const results = index.query([0.1, 0.2, ...], 5);
 * for (const r of results) {
 *   console.log(`${r.id}: ${r.score}`);
 * }
 * const json = index.save();
 * const loaded = VectorIndex.load(json);
 * ```
 */

/**
 * Result from a vector similarity search.
 */
export class SearchResult {
  /** Document ID */
  readonly id: string;

  /**
   * Similarity score (0.0 = dissimilar, 1.0 = identical).
   *
   * Computed as 1.0 - cosine_distance. For L2-normalized embeddings,
   * this equals the cosine similarity (dot product).
   */
  readonly score: number;

  /** Associated metadata provided when the vector was added */
  readonly metadata: Record<string, any>;

  constructor(config: {
    id: string;
    score: number;
    metadata: Record<string, any>;
  }) {
    this.id = config.id;
    this.score = config.score;
    this.metadata = config.metadata;
  }

  toString(): string {
    return `SearchResult(id: ${this.id}, score: ${this.score.toFixed(4)})`;
  }
}

/**
 * Vector index entry storing embedding and metadata.
 */
interface VectorEntry {
  id: string;
  embedding: Float32Array;
  metadata: Record<string, any>;
}

/**
 * Serialized vector index format for save/load.
 */
interface SerializedVectorIndex {
  version: number;
  dimensions: number;
  entries: Array<{
    id: string;
    embedding: number[];
    metadata: Record<string, any>;
  }>;
}

/**
 * Vector index for on-device similarity search.
 *
 * Each vector is associated with a string id and optional metadata.
 * The index uses cosine distance, which is correct for L2-normalized
 * embeddings produced by ev_embed.
 */
export class VectorIndex {
  /** Number of dimensions per embedding vector */
  readonly dimensions: number;

  /** Stored vectors indexed by ID */
  private readonly _entries: Map<string, VectorEntry>;

  /**
   * Create a new empty vector index.
   *
   * @param dimensions - Must match the embedding model's output size
   *   (e.g., 384 for all-MiniLM, 768 for nomic-embed-text)
   */
  constructor(config: { dimensions: number }) {
    this.dimensions = config.dimensions;
    this._entries = new Map();
  }

  /** Number of vectors in the index */
  get size(): number {
    return this._entries.size;
  }

  /** Whether the index is empty */
  get isEmpty(): boolean {
    return this._entries.size === 0;
  }

  /** All document IDs currently in the index */
  get ids(): string[] {
    return Array.from(this._entries.keys());
  }

  /**
   * Add a vector with an id and optional metadata.
   *
   * If an entry with the same id already exists, it is replaced.
   *
   * @throws {Error} if embedding length does not match dimensions
   */
  add(
    id: string,
    embedding: number[] | Float32Array,
    metadata?: Record<string, any>
  ): void {
    if (embedding.length !== this.dimensions) {
      throw new Error(
        `Embedding dimension ${embedding.length} does not match ` +
          `index dimension ${this.dimensions}`
      );
    }

    // Convert to Float32Array for efficient storage and computation
    const embeddingArray =
      embedding instanceof Float32Array
        ? embedding
        : new Float32Array(embedding);

    this._entries.set(id, {
      id,
      embedding: embeddingArray,
      metadata: metadata ?? {},
    });
  }

  /**
   * Query the index for the k nearest neighbors to embedding.
   *
   * Returns results sorted by similarity score (highest first).
   * Returns an empty array if the index is empty.
   *
   * @param embedding - Query vector
   * @param k - Number of nearest neighbors to return (default: 5)
   * @throws {Error} if embedding length does not match dimensions
   */
  query(embedding: number[] | Float32Array, k: number = 5): SearchResult[] {
    if (embedding.length !== this.dimensions) {
      throw new Error(
        `Query dimension ${embedding.length} does not match ` +
          `index dimension ${this.dimensions}`
      );
    }

    if (this.isEmpty) return [];

    // Convert query to Float32Array
    const queryArray =
      embedding instanceof Float32Array
        ? embedding
        : new Float32Array(embedding);

    // Compute cosine distance for all entries
    const results: Array<{ entry: VectorEntry; distance: number }> = [];

    for (const entry of this._entries.values()) {
      const distance = this._cosineDistance(queryArray, entry.embedding);
      results.push({ entry, distance });
    }

    // Sort by distance (ascending) and take top k
    results.sort((a, b) => a.distance - b.distance);
    const topK = results.slice(0, Math.min(k, results.length));

    // Convert to SearchResult with similarity score (1 - distance)
    return topK.map(
      (result) =>
        new SearchResult({
          id: result.entry.id,
          score: 1.0 - result.distance,
          metadata: result.entry.metadata,
        })
    );
  }

  /**
   * Delete a vector by id.
   *
   * @returns true if the entry was found and deleted, false otherwise
   */
  delete(id: string): boolean {
    return this._entries.delete(id);
  }

  /**
   * Get metadata for a specific document ID.
   *
   * @returns metadata object or null if id not found
   */
  getMetadata(id: string): Record<string, any> | null {
    const entry = this._entries.get(id);
    return entry ? entry.metadata : null;
  }

  /**
   * Check if an ID exists in the index.
   */
  has(id: string): boolean {
    return this._entries.has(id);
  }

  /**
   * Clear all entries from the index.
   */
  clear(): void {
    this._entries.clear();
  }

  /**
   * Save the index to a JSON-serializable object.
   *
   * Returns an object that can be JSON.stringify'd and later restored
   * with VectorIndex.load().
   */
  save(): SerializedVectorIndex {
    const entries = Array.from(this._entries.values()).map((entry) => ({
      id: entry.id,
      embedding: Array.from(entry.embedding),
      metadata: entry.metadata,
    }));

    return {
      version: 1,
      dimensions: this.dimensions,
      entries,
    };
  }

  /**
   * Load an index from a serialized object.
   *
   * @param data - Serialized index data from save()
   * @throws {Error} if data is malformed or version is unsupported
   */
  static load(data: SerializedVectorIndex): VectorIndex {
    if (data.version !== 1) {
      throw new Error(`Unsupported index version: ${data.version}`);
    }

    const index = new VectorIndex({ dimensions: data.dimensions });

    for (const entry of data.entries) {
      index.add(entry.id, entry.embedding, entry.metadata);
    }

    return index;
  }

  /**
   * Create a new empty index (factory for API consistency with load).
   */
  static create(config: { dimensions: number }): VectorIndex {
    return new VectorIndex(config);
  }

  /**
   * Compute cosine distance between two vectors.
   *
   * Returns a value in [0, 2] where:
   * - 0 = identical vectors (parallel, same direction)
   * - 1 = orthogonal vectors
   * - 2 = opposite vectors (parallel, opposite directions)
   *
   * For L2-normalized vectors: cosine_distance = 1 - cosine_similarity
   */
  private _cosineDistance(a: Float32Array, b: Float32Array): number {
    let dotProduct = 0;
    let normA = 0;
    let normB = 0;

    for (let i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = Math.sqrt(normA);
    normB = Math.sqrt(normB);

    // Avoid division by zero
    if (normA === 0 || normB === 0) {
      return 1; // orthogonal by convention
    }

    const cosineSimilarity = dotProduct / (normA * normB);

    // Clamp to [-1, 1] to handle floating point errors
    const clampedSimilarity = Math.max(-1, Math.min(1, cosineSimilarity));

    // Convert similarity to distance: distance = 1 - similarity
    return 1 - clampedSimilarity;
  }
}
