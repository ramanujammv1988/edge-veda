package com.edgeveda.sdk.examples

import com.edgeveda.sdk.EdgeVeda
import com.edgeveda.sdk.EdgeVedaConfig
import com.edgeveda.sdk.GenerateOptions
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * Example demonstrating improved streaming control with token-by-token iteration.
 *
 * The new streaming architecture allows for:
 * 1. Graceful cancellation between tokens
 * 2. Pause/resume functionality
 * 3. Interleaved operations during generation
 * 4. Better resource management
 */
object StreamingControlExample {

    /**
     * Example 1: Cancellable streaming with user interruption.
     *
     * User can cancel the stream at any time, and the cancellation
     * happens cleanly between tokens without blocking.
     */
    suspend fun cancellableStreamExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 1: Cancellable Streaming ===")
        
        val job = CoroutineScope(Dispatchers.Default).launch {
            try {
                edgeVeda.generateStream(
                    prompt = "Write a long story about a robot learning to paint.",
                    options = GenerateOptions(maxTokens = 500)
                ).collect { token ->
                    print(token)
                }
            } catch (e: CancellationException) {
                println("\n[Stream cancelled by user]")
            }
        }
        
        // Simulate user cancellation after 2 seconds
        delay(2000)
        println("\n[User pressed stop button]")
        job.cancelAndJoin()
        println("[Cancellation completed cleanly]")
    }

    /**
     * Example 2: Pause and resume streaming.
     *
     * Demonstrate pausing generation to process tokens or perform
     * other operations, then resuming.
     */
    suspend fun pauseResumeExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 2: Pause/Resume Streaming ===")
        
        var tokenCount = 0
        val pauseAt = 20
        
        edgeVeda.generateStream(
            prompt = "Explain quantum computing in simple terms.",
            options = GenerateOptions(maxTokens = 100)
        ).collect { token ->
            print(token)
            tokenCount++
            
            // Pause after certain number of tokens
            if (tokenCount == pauseAt) {
                println("\n[Pausing to analyze progress...]")
                delay(1000) // Simulate processing
                println("[Resuming generation]")
            }
        }
        
        println("\n[Generation complete: $tokenCount tokens]")
    }

    /**
     * Example 3: Interleaved operations during streaming.
     *
     * Perform other operations between tokens without blocking the stream.
     * This wasn't possible with the old callback-based approach.
     */
    suspend fun interleavedOperationsExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 3: Interleaved Operations ===")
        
        var tokenCount = 0
        val checkInterval = 10
        
        edgeVeda.generateStream(
            prompt = "List 20 programming best practices.",
            options = GenerateOptions(maxTokens = 200)
        ).collect { token ->
            print(token)
            tokenCount++
            
            // Every N tokens, check context usage
            if (tokenCount % checkInterval == 0) {
                val contextUsed = edgeVeda.getContextUsed()
                val contextSize = edgeVeda.getContextSize()
                val percentUsed = (contextUsed.toFloat() / contextSize * 100).toInt()
                println("\n[Context: $contextUsed/$contextSize ($percentUsed%)]")
            }
        }
        
        println("\n[Generation complete]")
    }

    /**
     * Example 4: Multiple concurrent streams with independent control.
     *
     * Run multiple streams in parallel and cancel/control them independently.
     */
    suspend fun concurrentStreamsExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 4: Concurrent Streams ===")
        
        val stream1 = CoroutineScope(Dispatchers.Default).launch {
            try {
                println("[Stream 1 starting]")
                edgeVeda.generateStream(
                    prompt = "Write a haiku about technology.",
                    options = GenerateOptions(maxTokens = 50)
                ).collect { token ->
                    print("1: $token")
                }
                println("\n[Stream 1 complete]")
            } catch (e: CancellationException) {
                println("\n[Stream 1 cancelled]")
            }
        }
        
        delay(100) // Small delay between streams
        
        val stream2 = CoroutineScope(Dispatchers.Default).launch {
            try {
                println("[Stream 2 starting]")
                edgeVeda.generateStream(
                    prompt = "Write a haiku about nature.",
                    options = GenerateOptions(maxTokens = 50)
                ).collect { token ->
                    print("2: $token")
                }
                println("\n[Stream 2 complete]")
            } catch (e: CancellationException) {
                println("\n[Stream 2 cancelled]")
            }
        }
        
        // Wait for both streams
        joinAll(stream1, stream2)
        println("[All streams complete]")
    }

    /**
     * Example 5: Rate-limited streaming for UI responsiveness.
     *
     * Control the rate of token emission to avoid overwhelming the UI.
     */
    suspend fun rateLimitedStreamExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 5: Rate-Limited Streaming ===")
        
        var tokenCount = 0
        val startTime = System.currentTimeMillis()
        
        edgeVeda.generateStream(
            prompt = "Describe the solar system.",
            options = GenerateOptions(maxTokens = 100)
        )
        .onEach { 
            // Rate limit: delay between tokens for smooth UI updates
            delay(50) 
        }
        .collect { token ->
            print(token)
            tokenCount++
        }
        
        val elapsedMs = System.currentTimeMillis() - startTime
        val tokensPerSecond = tokenCount.toFloat() / (elapsedMs / 1000f)
        println("\n[Complete: $tokenCount tokens in ${elapsedMs}ms (~${"%.1f".format(tokensPerSecond)} tokens/sec)]")
    }

    /**
     * Example 6: Conditional cancellation based on content.
     *
     * Cancel generation if certain content patterns are detected.
     */
    suspend fun conditionalCancellationExample(edgeVeda: EdgeVeda) {
        println("\n=== Example 6: Conditional Cancellation ===")
        
        val forbiddenWords = setOf("error", "fail", "crash")
        var fullText = ""
        
        try {
            edgeVeda.generateStream(
                prompt = "Write about software development challenges.",
                options = GenerateOptions(maxTokens = 200)
            ).collect { token ->
                fullText += token
                print(token)
                
                // Check for forbidden words
                if (forbiddenWords.any { fullText.lowercase().contains(it) }) {
                    println("\n[Content filter triggered - cancelling stream]")
                    throw CancellationException("Content policy violation")
                }
            }
        } catch (e: CancellationException) {
            println("[Stream cancelled: ${e.message}]")
        }
        
        println("\n[Check complete]")
    }

    /**
     * Main entry point to run all examples.
     */
    @JvmStatic
    suspend fun runAllExamples(edgeVeda: EdgeVeda) {
        println("=".repeat(60))
        println("Streaming Control Examples - Token-by-Token Architecture")
        println("=".repeat(60))
        
        // Run each example
        cancellableStreamExample(edgeVeda)
        delay(500)
        
        pauseResumeExample(edgeVeda)
        delay(500)
        
        interleavedOperationsExample(edgeVeda)
        delay(500)
        
        rateLimitedStreamExample(edgeVeda)
        delay(500)
        
        conditionalCancellationExample(edgeVeda)
        delay(500)
        
        // Note: Concurrent streams example requires model reload between streams
        // Uncomment if you want to test it:
        // concurrentStreamsExample(edgeVeda)
        
        println("\n" + "=".repeat(60))
        println("All examples complete!")
        println("=".repeat(60))
    }
}

/**
 * Usage example:
 *
 * ```kotlin
 * val edgeVeda = EdgeVeda.create(context)
 * edgeVeda.init("/path/to/model.gguf")
 *
 * // Run all examples
 * StreamingControlExample.runAllExamples(edgeVeda)
 *
 * // Or run individual examples
 * StreamingControlExample.cancellableStreamExample(edgeVeda)
 * StreamingControlExample.pauseResumeExample(edgeVeda)
 * // etc.
 *
 * edgeVeda.close()
 * ```
 */