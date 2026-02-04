/**
 * Example: Model cache management
 */

import {
  listCachedModels,
  getCacheSize,
  deleteCachedModel,
  clearCache,
  estimateStorageQuota,
} from '../src/index';

async function main() {
  console.log('Edge Veda - Cache Management Example\n');

  // Check storage quota
  console.log('Storage Quota:');
  const quota = await estimateStorageQuota();
  console.log(`  Used: ${(quota.usage / 1024 / 1024).toFixed(2)} MB`);
  console.log(`  Total: ${(quota.quota / 1024 / 1024).toFixed(2)} MB`);
  console.log(`  Available: ${(quota.available / 1024 / 1024).toFixed(2)} MB\n`);

  // List cached models
  console.log('Cached Models:');
  const models = await listCachedModels();

  if (models.length === 0) {
    console.log('  (none)\n');
  } else {
    for (const model of models) {
      const sizeMB = (model.size / 1024 / 1024).toFixed(2);
      const date = new Date(model.timestamp).toLocaleString();
      console.log(`  - ${model.modelId}`);
      console.log(`    Size: ${sizeMB} MB`);
      console.log(`    Precision: ${model.precision}`);
      console.log(`    Version: ${model.version}`);
      console.log(`    Cached: ${date}`);
      if (model.checksum) {
        console.log(`    Checksum: ${model.checksum.slice(0, 16)}...`);
      }
      console.log();
    }
  }

  // Get total cache size
  const totalSize = await getCacheSize();
  console.log(`Total Cache Size: ${(totalSize / 1024 / 1024).toFixed(2)} MB\n`);

  // Example: Delete a specific model
  if (models.length > 0) {
    const modelToDelete = models[0].modelId;
    console.log(`Example: Deleting model "${modelToDelete}"...`);
    // Uncomment to actually delete:
    // await deleteCachedModel(modelToDelete);
    // console.log('Deleted!\n');
    console.log('(Skipped - uncomment to actually delete)\n');
  }

  // Example: Clear all cache
  console.log('Example: Clear all cache...');
  // Uncomment to actually clear:
  // await clearCache();
  // console.log('All cache cleared!\n');
  console.log('(Skipped - uncomment to actually clear)\n');

  // Cache statistics
  console.log('Cache Statistics:');
  console.log(`  Number of models: ${models.length}`);
  console.log(`  Average model size: ${models.length > 0 ? (totalSize / models.length / 1024 / 1024).toFixed(2) : 0} MB`);
  console.log(`  Cache utilization: ${quota.quota > 0 ? ((totalSize / quota.quota) * 100).toFixed(2) : 0}%`);
}

// Run example
main().catch(console.error);
