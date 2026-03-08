/**
 * Example: Streaming text generation with Edge Veda
 */

import { EdgeVeda } from '../src/index';

async function main() {
  console.log('Edge Veda - Streaming Example\n');

  // Create instance with progress tracking
  const ai = new EdgeVeda({
    modelId: 'llama-3.2-1b',
    device: 'auto',
    precision: 'fp16',
    onProgress: (progress) => {
      const percent = progress.progress.toFixed(1);
      console.log(`[${progress.stage}] ${percent}%: ${progress.message || ''}`);
    },
    onError: (error) => {
      console.error('Error:', error.message);
    },
  });

  // Initialize
  console.log('Initializing...');
  await ai.init();
  console.log('Ready!\n');

  // Stream generation
  console.log('Generating (streaming)...\n');
  console.log('---');

  const startTime = Date.now();
  let tokenCount = 0;

  for await (const chunk of ai.generateStream({
    prompt: 'Write a haiku about programming:',
    maxTokens: 100,
    temperature: 0.8,
  })) {
    // Print token as it arrives
    process.stdout.write(chunk.token);
    tokenCount++;

    if (chunk.done) {
      console.log('\n---\n');
      console.log('Stream complete!');

      if (chunk.stats) {
        console.log(`\nStatistics:`);
        console.log(`  Tokens: ${chunk.tokensGenerated}`);
        console.log(`  Time: ${chunk.stats.timeMs.toFixed(0)}ms`);
        console.log(`  Speed: ${chunk.stats.tokensPerSecond.toFixed(2)} tokens/sec`);
        console.log(`  Stop reason: ${chunk.stats.stopReason || 'unknown'}`);
      }
    }
  }

  // Clean up
  console.log('\nCleaning up...');
  await ai.terminate();
  console.log('Done!');
}

// Run example
main().catch(console.error);
