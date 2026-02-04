#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

/**
 * Edge Veda iOS Native Module
 * TurboModule implementation for on-device LLM inference
 */

@interface RCT_EXTERN_MODULE(EdgeVeda, RCTEventEmitter)

// Initialize model
RCT_EXTERN_METHOD(initialize:(NSString *)modelPath
                  config:(NSString *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Generate text
RCT_EXTERN_METHOD(generate:(NSString *)prompt
                  options:(NSString *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Generate streaming
RCT_EXTERN_METHOD(generateStream:(NSString *)prompt
                  options:(NSString *)options
                  requestId:(NSString *)requestId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Cancel generation
RCT_EXTERN_METHOD(cancelGeneration:(NSString *)requestId
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Get memory usage
RCT_EXTERN_METHOD(getMemoryUsage:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Get model info
RCT_EXTERN_METHOD(getModelInfo:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Check if model loaded
RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(isModelLoaded)

// Unload model
RCT_EXTERN_METHOD(unloadModel:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Validate model
RCT_EXTERN_METHOD(validateModel:(NSString *)modelPath
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Get GPU devices
RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(getAvailableGpuDevices)

// Required for TurboModule
+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
