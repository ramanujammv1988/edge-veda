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

// Reset context
RCT_EXTERN_METHOD(resetContext:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Event emitter bookkeeping (required by RCTEventEmitter)
RCT_EXTERN_METHOD(addListener:(NSString *)eventName)
RCT_EXTERN_METHOD(removeListeners:(NSInteger)count)

// Vision Inference

RCT_EXTERN_METHOD(initVision:(NSString *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(describeImage:(NSString *)rgbBytes
                  width:(NSInteger)width
                  height:(NSInteger)height
                  prompt:(NSString *)prompt
                  params:(NSString *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(freeVision:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(isVisionLoaded)

// Embedding

RCT_EXTERN_METHOD(embed:(NSString *)text
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

// Whisper STT

RCT_EXTERN_METHOD(initWhisper:(NSString *)modelPath
                  config:(NSString *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(transcribeAudio:(NSString *)pcmBase64
                  nSamples:(NSInteger)nSamples
                  params:(NSString *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(freeWhisper:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(isWhisperLoaded)

// Image Generation

RCT_EXTERN_METHOD(initImageGeneration:(NSString *)modelPath
                  config:(NSString *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(generateImage:(NSString *)params
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(freeImageGeneration:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN__BLOCKING_SYNCHRONOUS_METHOD(isImageGenerationLoaded)

// Required for TurboModule
+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
