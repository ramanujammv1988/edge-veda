#import "EdgeVeda.h"
#import <React/RCTLog.h>
#include "edge_veda.h"
#include <string>
#include <unordered_map>

@implementation EdgeVeda {
    std::unordered_map<int, ev_context> _contexts;
    std::unordered_map<int, ev_stream> _streams;
    int _nextHandle;
    int _nextStreamHandle;
}

RCT_EXPORT_MODULE()

- (instancetype)init {
    self = [super init];
    if (self) {
        _nextHandle = 1;
        _nextStreamHandle = 1;
    }
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

RCT_EXPORT_METHOD(initialize:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *modelPath = config[@"modelPath"];
        if (!modelPath) {
            reject(@"ERR_INVALID_PARAM", @"modelPath is required", nil);
            return;
        }

        ev_config cfg;
        ev_config_default(&cfg);
        cfg.model_path = [modelPath UTF8String];
        cfg.num_threads = [config[@"numThreads"] intValue] ?: 4;
        cfg.context_size = [config[@"contextSize"] intValue] ?: 2048;
        cfg.gpu_layers = [config[@"gpuLayers"] intValue] ?: -1;

        ev_error_t error;
        ev_context ctx = ev_init(&cfg, &error);

        if (!ctx) {
            reject(@"ERR_INIT", @(ev_error_string(error)), nil);
            return;
        }

        int handle = self->_nextHandle++;
        self->_contexts[handle] = ctx;
        resolve(@(handle));
    });
}

RCT_EXPORT_METHOD(generate:(int)handle
                  prompt:(NSString *)prompt
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        auto it = self->_contexts.find(handle);
        if (it == self->_contexts.end()) {
            reject(@"ERR_INVALID", @"Invalid handle", nil);
            return;
        }

        ev_generation_params params;
        ev_generation_params_default(&params);
        if (options[@"maxTokens"]) params.max_tokens = [options[@"maxTokens"] intValue];
        if (options[@"temperature"]) params.temperature = [options[@"temperature"] floatValue];
        if (options[@"topP"]) params.top_p = [options[@"topP"] floatValue];
        if (options[@"topK"]) params.top_k = [options[@"topK"] intValue];

        NSTimeInterval start = [[NSDate date] timeIntervalSince1970];
        char *output = nullptr;
        ev_error_t error = ev_generate(it->second, [prompt UTF8String], &params, &output);

        if (error != EV_SUCCESS) {
            reject(@"ERR_GENERATE", @(ev_error_string(error)), nil);
            return;
        }

        NSTimeInterval latencyMs = ([[NSDate date] timeIntervalSince1970] - start) * 1000;
        NSString *text = @(output);
        ev_free_string(output);

        resolve(@{
            @"text": text,
            @"promptTokens": @(0),
            @"completionTokens": @(0),
            @"totalTokens": @(0),
            @"latencyMs": @(latencyMs),
            @"tokensPerSecond": [NSNull null],
        });
    });
}

RCT_EXPORT_METHOD(startStream:(int)handle
                  prompt:(NSString *)prompt
                  options:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        auto it = self->_contexts.find(handle);
        if (it == self->_contexts.end()) {
            reject(@"ERR_INVALID", @"Invalid handle", nil);
            return;
        }

        ev_generation_params params;
        ev_generation_params_default(&params);
        if (options[@"maxTokens"]) params.max_tokens = [options[@"maxTokens"] intValue];
        if (options[@"temperature"]) params.temperature = [options[@"temperature"] floatValue];

        ev_error_t error;
        ev_stream stream = ev_generate_stream(it->second, [prompt UTF8String], &params, &error);

        if (!stream) {
            reject(@"ERR_STREAM", @(ev_error_string(error)), nil);
            return;
        }

        int streamHandle = self->_nextStreamHandle++;
        self->_streams[streamHandle] = stream;
        resolve(@(streamHandle));
    });
}

RCT_EXPORT_METHOD(nextToken:(int)streamHandle
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        auto it = self->_streams.find(streamHandle);
        if (it == self->_streams.end()) {
            resolve([NSNull null]);
            return;
        }

        ev_error_t error;
        char *token = ev_stream_next(it->second, &error);

        if (!token) {
            resolve([NSNull null]);
            return;
        }

        NSString *tokenStr = @(token);
        ev_free_string(token);
        resolve(@{@"token": tokenStr});
    });
}

RCT_EXPORT_METHOD(cancelStream:(int)streamHandle) {
    auto it = _streams.find(streamHandle);
    if (it != _streams.end()) {
        ev_stream_cancel(it->second);
    }
}

RCT_EXPORT_METHOD(getMemoryUsage:(int)handle
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    auto it = _contexts.find(handle);
    if (it == _contexts.end()) {
        reject(@"ERR_INVALID", @"Invalid handle", nil);
        return;
    }

    ev_memory_stats stats;
    ev_error_t error = ev_get_memory_usage(it->second, &stats);
    if (error != EV_SUCCESS) {
        reject(@"ERR_MEMORY", @(ev_error_string(error)), nil);
        return;
    }

    resolve(@{
        @"currentBytes": @(stats.current_bytes),
        @"peakBytes": @(stats.peak_bytes),
        @"limitBytes": @(stats.limit_bytes),
        @"modelBytes": @(stats.model_bytes),
        @"contextBytes": @(stats.context_bytes),
    });
}

RCT_EXPORT_METHOD(dispose:(int)handle) {
    auto it = _contexts.find(handle);
    if (it != _contexts.end()) {
        ev_free(it->second);
        _contexts.erase(it);
    }
}

@end
