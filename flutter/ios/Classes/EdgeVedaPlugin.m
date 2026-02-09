#import "EdgeVedaPlugin.h"
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <os/proc.h>

#pragma mark - ThermalStreamHandler

/// Stream handler for iOS thermal state change push notifications.
/// Sends events via EventChannel when NSProcessInfoThermalStateDidChangeNotification fires.
@interface EVThermalStreamHandler : NSObject<FlutterStreamHandler>
@end

@implementation EVThermalStreamHandler {
    FlutterEventSink _eventSink;
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(thermalStateDidChange:)
               name:NSProcessInfoThermalStateDidChangeNotification
             object:nil];

    // Send initial thermal state immediately on listen
    [self sendCurrentThermalState];
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSProcessInfoThermalStateDidChangeNotification
                                                  object:nil];
    _eventSink = nil;
    return nil;
}

- (void)thermalStateDidChange:(NSNotification *)notification {
    [self sendCurrentThermalState];
}

- (void)sendCurrentThermalState {
    if (!_eventSink) return;

    NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
    double timestampMs = [[NSDate date] timeIntervalSince1970] * 1000.0;

    // Dispatch to main queue to ensure thread safety for EventChannel
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_eventSink) {
            self->_eventSink(@{
                @"thermalState": @((int)state),
                @"timestamp": @(timestampMs),
            });
        }
    });
}

@end

#pragma mark - EdgeVedaPlugin

@implementation EdgeVedaPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // MethodChannel for on-demand telemetry polling
    FlutterMethodChannel *methodChannel = [FlutterMethodChannel
        methodChannelWithName:@"com.edgeveda.edge_veda/telemetry"
              binaryMessenger:[registrar messenger]];

    EdgeVedaPlugin *instance = [[EdgeVedaPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:methodChannel];

    // EventChannel for push thermal state notifications
    FlutterEventChannel *thermalChannel = [FlutterEventChannel
        eventChannelWithName:@"com.edgeveda.edge_veda/thermal"
             binaryMessenger:[registrar messenger]];
    [thermalChannel setStreamHandler:[[EVThermalStreamHandler alloc] init]];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([@"getThermalState" isEqualToString:call.method]) {
        [self handleGetThermalState:result];
    } else if ([@"getBatteryLevel" isEqualToString:call.method]) {
        [self handleGetBatteryLevel:result];
    } else if ([@"getBatteryState" isEqualToString:call.method]) {
        [self handleGetBatteryState:result];
    } else if ([@"getMemoryRSS" isEqualToString:call.method]) {
        [self handleGetMemoryRSS:result];
    } else if ([@"getAvailableMemory" isEqualToString:call.method]) {
        [self handleGetAvailableMemory:result];
    } else if ([@"isLowPowerMode" isEqualToString:call.method]) {
        [self handleIsLowPowerMode:result];
    } else if ([@"shareFile" isEqualToString:call.method]) {
        [self handleShareFile:call result:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Thermal

/// Returns iOS thermal state as int: 0=nominal, 1=fair, 2=serious, 3=critical
- (void)handleGetThermalState:(FlutterResult)result {
    NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
    result(@((int)state));
}

#pragma mark - Battery

/// Returns battery level as double: 0.0 to 1.0, or -1.0 if unknown
- (void)handleGetBatteryLevel:(FlutterResult)result {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    float level = [[UIDevice currentDevice] batteryLevel];
    result(@((double)level));
}

/// Returns battery state as int: 0=unknown, 1=unplugged, 2=charging, 3=full
- (void)handleGetBatteryState:(FlutterResult)result {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    UIDeviceBatteryState state = [[UIDevice currentDevice] batteryState];
    result(@((int)state));
}

#pragma mark - Memory

/// Returns process RSS (resident set size) in bytes via task_info.
/// Returns 0 on failure.
- (void)handleGetMemoryRSS:(FlutterResult)result {
    struct mach_task_basic_info info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t kerr = task_info(mach_task_self(),
                                   MACH_TASK_BASIC_INFO,
                                   (task_info_t)&info,
                                   &size);
    if (kerr == KERN_SUCCESS) {
        result(@((long long)info.resident_size));
    } else {
        result(@(0));
    }
}

/// Returns available memory in bytes via os_proc_available_memory() (iOS 13+).
- (void)handleGetAvailableMemory:(FlutterResult)result {
    size_t available = os_proc_available_memory();
    result(@((long long)available));
}

#pragma mark - Power

/// Returns whether iOS Low Power Mode is enabled.
- (void)handleIsLowPowerMode:(FlutterResult)result {
    BOOL lowPower = [[NSProcessInfo processInfo] isLowPowerModeEnabled];
    result(@(lowPower));
}

#pragma mark - Share

/// Present iOS share sheet for a file at the given path.
- (void)handleShareFile:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSString *filePath = call.arguments[@"path"];
    if (!filePath) {
        result([FlutterError errorWithCode:@"INVALID_ARG"
                                   message:@"Missing 'path' argument"
                                   details:nil]);
        return;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        result([FlutterError errorWithCode:@"FILE_NOT_FOUND"
                                   message:@"File not found"
                                   details:filePath]);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIActivityViewController *activityVC =
            [[UIActivityViewController alloc] initWithActivityItems:@[fileURL]
                                             applicationActivities:nil];

        UIViewController *rootVC =
            [UIApplication sharedApplication].keyWindow.rootViewController;
        if (rootVC) {
            // iPad popover anchor
            activityVC.popoverPresentationController.sourceView = rootVC.view;
            activityVC.popoverPresentationController.sourceRect =
                CGRectMake(CGRectGetMidX(rootVC.view.bounds),
                           CGRectGetMaxY(rootVC.view.bounds) - 100,
                           0, 0);
            [rootVC presentViewController:activityVC animated:YES completion:nil];
            result(@(YES));
        } else {
            result([FlutterError errorWithCode:@"NO_VIEW"
                                       message:@"No root view controller"
                                       details:nil]);
        }
    });
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // Cleanup handled by ARC and notification center observers
}

@end
