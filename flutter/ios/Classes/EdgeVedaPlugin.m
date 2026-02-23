#import "EdgeVedaPlugin.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <EventKit/EventKit.h>
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

#pragma mark - AudioCaptureStreamHandler

/// Stream handler for microphone audio capture via AVAudioEngine.
/// Delivers 16kHz mono float32 PCM samples via EventChannel.
@interface EVAudioCaptureHandler : NSObject<FlutterStreamHandler>
@property (nonatomic, strong) AVAudioEngine *audioEngine;
@end

@implementation EVAudioCaptureHandler {
    FlutterEventSink _eventSink;
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;

    @try {
        self.audioEngine = [[AVAudioEngine alloc] init];
        AVAudioInputNode *inputNode = [self.audioEngine inputNode];

        // Use the input node's native hardware format for the tap.
        // On iPhone this is typically 48kHz mono Float32.
        // You CANNOT install a tap with an arbitrary format on AVAudioInputNode --
        // it must match the hardware format. We convert to 16kHz afterwards.
        AVAudioFormat *nativeFormat = [inputNode outputFormatForBus:0];

        // Defensive check: simulator may return invalid format (0 Hz, 0 channels).
        // Bail out gracefully instead of crashing on division-by-zero or nil converter.
        if (!nativeFormat || nativeFormat.sampleRate < 1.0 || nativeFormat.channelCount == 0) {
            NSString *detail = [NSString stringWithFormat:
                @"sampleRate=%.0f channels=%u",
                nativeFormat ? nativeFormat.sampleRate : 0.0,
                (unsigned)(nativeFormat ? nativeFormat.channelCount : 0)];
            self.audioEngine = nil;
            return [FlutterError errorWithCode:@"AUDIO_FORMAT_UNAVAILABLE"
                                       message:@"Microphone audio format is invalid (simulator may lack audio input)"
                                       details:detail];
        }

        // Target format: 16kHz mono float32 (what whisper.cpp expects)
        AVAudioFormat *whisperFormat = [[AVAudioFormat alloc]
            initWithCommonFormat:AVAudioPCMFormatFloat32
                      sampleRate:16000.0
                        channels:1
                     interleaved:NO];

        // Create a converter from native hardware format -> 16kHz mono
        AVAudioConverter *converter = [[AVAudioConverter alloc]
            initFromFormat:nativeFormat
                  toFormat:whisperFormat];

        if (!converter) {
            self.audioEngine = nil;
            return [FlutterError errorWithCode:@"AUDIO_CONVERTER_FAILED"
                                       message:@"Failed to create audio format converter"
                                       details:nil];
        }

        // Buffer size in native sample rate frames (~300ms worth)
        AVAudioFrameCount tapBufferSize =
            (AVAudioFrameCount)(nativeFormat.sampleRate * 0.3);

        [inputNode installTapOnBus:0
                        bufferSize:tapBufferSize
                            format:nativeFormat
                             block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
            // Calculate output capacity: proportional to sample rate ratio
            double ratio = 16000.0 / nativeFormat.sampleRate;
            AVAudioFrameCount outputCapacity =
                (AVAudioFrameCount)(buffer.frameLength * ratio) + 1;

            AVAudioPCMBuffer *converted = [[AVAudioPCMBuffer alloc]
                initWithPCMFormat:whisperFormat
                    frameCapacity:outputCapacity];

            // Reset converter state before each conversion.
            // AVAudioConverter is stateful -- after seeing EndOfStream it
            // permanently stops producing output. reset() clears that state.
            [converter reset];

            NSError *convError = nil;
            __block BOOL inputConsumed = NO;
            AVAudioConverterOutputStatus status = [converter
                convertToBuffer:converted
                          error:&convError
         withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets,
                                              AVAudioConverterInputStatus *outStatus) {
                if (inputConsumed) {
                    *outStatus = AVAudioConverterInputStatus_EndOfStream;
                    return nil;
                }
                inputConsumed = YES;
                *outStatus = AVAudioConverterInputStatus_HaveData;
                return buffer;
            }];

            if (status == AVAudioConverterOutputStatus_HaveData && !convError) {
                const float *channelData = converted.floatChannelData[0];
                NSUInteger frameLength = converted.frameLength;

                // Copy to FlutterStandardTypedData (Float32)
                NSData *pcmData = [NSData dataWithBytes:channelData
                                                 length:frameLength * sizeof(float)];
                FlutterStandardTypedData *typedData =
                    [FlutterStandardTypedData typedDataWithFloat32:pcmData];

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self->_eventSink) {
                        self->_eventSink(typedData);
                    }
                });
            }
        }];

        NSError *error;
        [self.audioEngine startAndReturnError:&error];
        if (error) {
            [self.audioEngine.inputNode removeTapOnBus:0];
            self.audioEngine = nil;
            return [FlutterError errorWithCode:@"AUDIO_ERROR"
                                       message:error.localizedDescription
                                       details:nil];
        }
        return nil;
    } @catch (NSException *exception) {
        // AVAudioEngine can throw NSException (e.g., invalid format on simulator).
        // Catch and return as FlutterError instead of crashing the app.
        self.audioEngine = nil;
        return [FlutterError errorWithCode:@"AUDIO_EXCEPTION"
                                   message:exception.reason ?: @"Audio engine exception"
                                   details:exception.name];
    }
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    [self.audioEngine.inputNode removeTapOnBus:0];
    [self.audioEngine stop];
    self.audioEngine = nil;
    _eventSink = nil;
    return nil;
}

@end

#pragma mark - TtsStreamHandler

/// Stream handler for TTS events (word boundaries, start/finish/cancel).
/// Also serves as AVSpeechSynthesizerDelegate to receive speech callbacks.
@interface EVTtsHandler : NSObject<FlutterStreamHandler, AVSpeechSynthesizerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synthesizer;
- (void)speakText:(NSString *)text voiceId:(NSString *)voiceId rate:(NSNumber *)rate pitch:(NSNumber *)pitch volume:(NSNumber *)volume;
- (BOOL)stop;
- (BOOL)pause;
- (BOOL)resume;
- (NSArray<NSDictionary *> *)availableVoices;
@end

@implementation EVTtsHandler {
    FlutterEventSink _eventSink;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _synthesizer = [[AVSpeechSynthesizer alloc] init];
        _synthesizer.delegate = self;
    }
    return self;
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    _eventSink = nil;
    return nil;
}

#pragma mark - TTS Actions

- (void)speakText:(NSString *)text voiceId:(NSString *)voiceId rate:(NSNumber *)rate pitch:(NSNumber *)pitch volume:(NSNumber *)volume {
    AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:text];

    if (voiceId && ![voiceId isEqual:[NSNull null]]) {
        AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithIdentifier:voiceId];
        if (voice) {
            utterance.voice = voice;
        }
    }

    utterance.rate = (rate && ![rate isEqual:[NSNull null]]) ? [rate floatValue] : AVSpeechUtteranceDefaultSpeechRate;
    utterance.pitchMultiplier = (pitch && ![pitch isEqual:[NSNull null]]) ? [pitch floatValue] : 1.0f;
    utterance.volume = (volume && ![volume isEqual:[NSNull null]]) ? [volume floatValue] : 1.0f;

    [_synthesizer speakUtterance:utterance];
}

- (BOOL)stop {
    return [_synthesizer stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (BOOL)pause {
    return [_synthesizer pauseSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}

- (BOOL)resume {
    return [_synthesizer continueSpeaking];
}

- (NSArray<NSDictionary *> *)availableVoices {
    NSArray<AVSpeechSynthesisVoice *> *allVoices = [AVSpeechSynthesisVoice speechVoices];

    // Filter to enhanced+ quality voices (skip old robotic ones)
    NSMutableArray<NSDictionary *> *enhanced = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *all = [NSMutableArray array];

    for (AVSpeechSynthesisVoice *voice in allVoices) {
        NSDictionary *dict = @{
            @"id": voice.identifier,
            @"name": voice.name,
            @"language": voice.language,
            @"quality": @((int)voice.quality),
        };

        [all addObject:dict];

        if ((int)voice.quality >= AVSpeechSynthesisVoiceQualityEnhanced) {
            [enhanced addObject:dict];
        }
    }

    // Return enhanced voices if any exist, otherwise fall back to all
    return enhanced.count > 0 ? enhanced : all;
}

#pragma mark - AVSpeechSynthesizerDelegate

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer willSpeakRangeOfSpeechString:(NSRange)characterRange utterance:(AVSpeechUtterance *)utterance {
    if (!_eventSink) return;

    NSString *word = [utterance.speechString substringWithRange:characterRange];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_eventSink) {
            self->_eventSink(@{
                @"type": @"wordBoundary",
                @"start": @(characterRange.location),
                @"length": @(characterRange.length),
                @"text": word ?: @"",
            });
        }
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!_eventSink) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_eventSink) {
            self->_eventSink(@{@"type": @"start"});
        }
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!_eventSink) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_eventSink) {
            self->_eventSink(@{@"type": @"finish"});
        }
    });
}

- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didCancelSpeechUtterance:(AVSpeechUtterance *)utterance {
    if (!_eventSink) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_eventSink) {
            self->_eventSink(@{@"type": @"cancel"});
        }
    });
}

@end

#pragma mark - EdgeVedaPlugin

@implementation EdgeVedaPlugin {
    EVTtsHandler *_ttsHandler;
}

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

    // EventChannel for microphone audio capture (16kHz mono float32 PCM)
    FlutterEventChannel *audioChannel = [FlutterEventChannel
        eventChannelWithName:@"com.edgeveda.edge_veda/audio_capture"
             binaryMessenger:[registrar messenger]];
    [audioChannel setStreamHandler:[[EVAudioCaptureHandler alloc] init]];

    // EventChannel for TTS events (word boundaries, start/finish/cancel)
    EVTtsHandler *ttsHandler = [[EVTtsHandler alloc] init];
    instance->_ttsHandler = ttsHandler;
    FlutterEventChannel *ttsChannel = [FlutterEventChannel
        eventChannelWithName:@"com.edgeveda.edge_veda/tts_events"
             binaryMessenger:[registrar messenger]];
    [ttsChannel setStreamHandler:ttsHandler];
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
    } else if ([@"requestMicrophonePermission" isEqualToString:call.method]) {
        [self handleRequestMicrophonePermission:result];
    } else if ([@"shareFile" isEqualToString:call.method]) {
        [self handleShareFile:call result:result];
    } else if ([@"checkDetectivePermissions" isEqualToString:call.method]) {
        [self handleCheckDetectivePermissions:result];
    } else if ([@"requestDetectivePermissions" isEqualToString:call.method]) {
        [self handleRequestDetectivePermissions:result];
    } else if ([@"getPhotoInsights" isEqualToString:call.method]) {
        [self handleGetPhotoInsights:call result:result];
    } else if ([@"getCalendarInsights" isEqualToString:call.method]) {
        [self handleGetCalendarInsights:call result:result];
    } else if ([@"getFreeDiskSpace" isEqualToString:call.method]) {
        [self handleGetFreeDiskSpace:result];
    } else if ([@"configureVoicePipelineAudio" isEqualToString:call.method]) {
        [self handleConfigureVoicePipelineAudio:result];
    } else if ([@"resetAudioSession" isEqualToString:call.method]) {
        [self handleResetAudioSession:result];
    } else if ([@"tts_speak" isEqualToString:call.method]) {
        NSDictionary *args = call.arguments;
        [_ttsHandler speakText:args[@"text"]
                       voiceId:args[@"voiceId"]
                          rate:args[@"rate"]
                         pitch:args[@"pitch"]
                        volume:args[@"volume"]];
        result(@(YES));
    } else if ([@"tts_stop" isEqualToString:call.method]) {
        [_ttsHandler stop];
        result(@(YES));
    } else if ([@"tts_pause" isEqualToString:call.method]) {
        [_ttsHandler pause];
        result(@(YES));
    } else if ([@"tts_resume" isEqualToString:call.method]) {
        [_ttsHandler resume];
        result(@(YES));
    } else if ([@"tts_voices" isEqualToString:call.method]) {
        result([_ttsHandler availableVoices]);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

#pragma mark - Voice Pipeline Audio Session

/// Configure AVAudioSession for voice pipeline: PlayAndRecord + Default mode.
/// Enables simultaneous mic capture + TTS playback at full speaker volume.
///
/// We intentionally use AVAudioSessionModeDefault instead of VoiceChat because:
/// - VoiceChat mode is designed for phone-to-ear conversations and applies
///   heavy AGC, noise suppression, and volume reduction that degrades both
///   speaker output volume and microphone quality for Whisper STT.
/// - PlayAndRecord category inherently enables echo cancellation on iOS
///   regardless of mode — VoiceChat is NOT required for echo cancellation.
/// - DefaultToSpeaker routes audio to loudspeaker at full volume.
/// - AllowBluetooth lets users use AirPods/headsets for voice conversations.
- (void)handleConfigureVoicePipelineAudio:(FlutterResult)result {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    // PlayAndRecord allows simultaneous mic input + speaker output.
    // DefaultToSpeaker routes TTS to loudspeaker instead of earpiece.
    // AllowBluetooth enables Bluetooth headset/AirPods for voice.
    if (![session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:(AVAudioSessionCategoryOptionDefaultToSpeaker |
                               AVAudioSessionCategoryOptionAllowBluetooth)
                        error:&error]) {
        result([FlutterError errorWithCode:@"AUDIO_SESSION"
                                   message:@"Failed to set audio session category"
                                   details:error.localizedDescription]);
        return;
    }

    // Default mode preserves natural speaker volume and mic sensitivity.
    // Echo cancellation is provided by PlayAndRecord category, not by the mode.
    if (![session setMode:AVAudioSessionModeDefault error:&error]) {
        result([FlutterError errorWithCode:@"AUDIO_SESSION"
                                   message:@"Failed to set audio session mode"
                                   details:error.localizedDescription]);
        return;
    }

    if (![session setActive:YES error:&error]) {
        result([FlutterError errorWithCode:@"AUDIO_SESSION"
                                   message:@"Failed to activate audio session"
                                   details:error.localizedDescription]);
        return;
    }

    result(@(YES));
}

/// Reset the audio session after voice pipeline stops.
/// Deactivates the session and notifies other audio apps they can resume.
- (void)handleResetAudioSession:(FlutterResult)result {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error = nil;

    if (![session setActive:NO
                withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                      error:&error]) {
        result([FlutterError errorWithCode:@"AUDIO_SESSION"
                                   message:@"Failed to deactivate audio session"
                                   details:error.localizedDescription]);
        return;
    }

    result(@(YES));
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

#pragma mark - Storage

/// Returns free disk space in bytes via NSFileManager.
/// Returns -1 on failure.
- (void)handleGetFreeDiskSpace:(FlutterResult)result {
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfFileSystemForPath:NSHomeDirectory()
        error:&error];
    if (error || !attrs) {
        result(@(-1));
        return;
    }
    NSNumber *freeSpace = attrs[NSFileSystemFreeSize];
    result(@([freeSpace longLongValue]));
}

#pragma mark - Power

/// Returns whether iOS Low Power Mode is enabled.
- (void)handleIsLowPowerMode:(FlutterResult)result {
    BOOL lowPower = [[NSProcessInfo processInfo] isLowPowerModeEnabled];
    result(@(lowPower));
}

#pragma mark - Microphone Permission

/// Request microphone recording permission from the user.
/// Returns YES if granted, NO if denied.
- (void)handleRequestMicrophonePermission:(FlutterResult)result {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            result(@(granted));
        });
    }];
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

#pragma mark - Detective Permissions

/// Check current photo and calendar permission status without prompting.
- (void)handleCheckDetectivePermissions:(FlutterResult)result {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Check Photos permission
        NSString *photosStatus;
        if (@available(iOS 14, *)) {
            PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
            switch (status) {
                case PHAuthorizationStatusAuthorized: photosStatus = @"granted"; break;
                case PHAuthorizationStatusLimited: photosStatus = @"limited"; break;
                case PHAuthorizationStatusDenied: photosStatus = @"denied"; break;
                case PHAuthorizationStatusRestricted: photosStatus = @"denied"; break;
                case PHAuthorizationStatusNotDetermined: photosStatus = @"notDetermined"; break;
                default: photosStatus = @"notDetermined"; break;
            }
        } else {
            PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
            switch (status) {
                case PHAuthorizationStatusAuthorized: photosStatus = @"granted"; break;
                case PHAuthorizationStatusDenied: photosStatus = @"denied"; break;
                case PHAuthorizationStatusRestricted: photosStatus = @"denied"; break;
                case PHAuthorizationStatusNotDetermined: photosStatus = @"notDetermined"; break;
                default: photosStatus = @"notDetermined"; break;
            }
        }

        // Check Calendar permission
        NSString *calendarStatus;
        EKAuthorizationStatus ekStatus = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
        switch (ekStatus) {
            case EKAuthorizationStatusAuthorized: calendarStatus = @"granted"; break;
            case EKAuthorizationStatusDenied: calendarStatus = @"denied"; break;
            case EKAuthorizationStatusRestricted: calendarStatus = @"denied"; break;
            case EKAuthorizationStatusNotDetermined: calendarStatus = @"notDetermined"; break;
            default: calendarStatus = @"notDetermined"; break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            result(@{@"photos": photosStatus, @"calendar": calendarStatus});
        });
    });
}

/// Request photo and calendar permissions sequentially (photos first, then calendar).
- (void)handleRequestDetectivePermissions:(FlutterResult)result {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Step 1: Request Photos permission
        dispatch_semaphore_t photoSem = dispatch_semaphore_create(0);
        __block NSString *photosStatus = @"denied";

        if (@available(iOS 14, *)) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                switch (status) {
                    case PHAuthorizationStatusAuthorized: photosStatus = @"granted"; break;
                    case PHAuthorizationStatusLimited: photosStatus = @"limited"; break;
                    default: photosStatus = @"denied"; break;
                }
                dispatch_semaphore_signal(photoSem);
            }];
        } else {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                photosStatus = (status == PHAuthorizationStatusAuthorized) ? @"granted" : @"denied";
                dispatch_semaphore_signal(photoSem);
            }];
        }
        dispatch_semaphore_wait(photoSem, DISPATCH_TIME_FOREVER);

        // Step 2: Request Calendar permission
        dispatch_semaphore_t calSem = dispatch_semaphore_create(0);
        __block NSString *calendarStatus = @"denied";
        EKEventStore *eventStore = [[EKEventStore alloc] init];

        if (@available(iOS 17.0, *)) {
            [eventStore requestFullAccessToEventsWithCompletion:^(BOOL granted, NSError *error) {
                calendarStatus = granted ? @"granted" : @"denied";
                dispatch_semaphore_signal(calSem);
            }];
        } else {
            [eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
                calendarStatus = granted ? @"granted" : @"denied";
                dispatch_semaphore_signal(calSem);
            }];
        }
        dispatch_semaphore_wait(calSem, DISPATCH_TIME_FOREVER);

        dispatch_async(dispatch_get_main_queue(), ^{
            result(@{@"photos": photosStatus, @"calendar": calendarStatus});
        });
    });
}

#pragma mark - Photo Insights

/// Helper: Convert NSDate weekday to day name string.
static NSString* dayNameFromWeekday(NSInteger weekday) {
    // NSCalendar weekday: 1=Sunday, 2=Monday, ..., 7=Saturday
    static NSArray *dayNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dayNames = @[@"Sun", @"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat"];
    });
    if (weekday >= 1 && weekday <= 7) return dayNames[weekday - 1];
    return @"Unknown";
}

/// Fetch photo metadata and return lightly processed summaries.
- (void)handleGetPhotoInsights:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;
    int limit = args[@"limit"] ? [args[@"limit"] intValue] : 500;
    int sinceDays = args[@"sinceDays"] ? [args[@"sinceDays"] intValue] : 30;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Check permission
        BOOL hasAccess = NO;
        if (@available(iOS 14, *)) {
            PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
            hasAccess = (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited);
        } else {
            hasAccess = ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusAuthorized);
        }

        if (!hasAccess) {
            dispatch_async(dispatch_get_main_queue(), ^{
                result(@{
                    @"totalPhotos": @(0),
                    @"dayOfWeekCounts": @{},
                    @"hourOfDayCounts": @{},
                    @"topLocations": @[],
                    @"photosWithLocation": @(0),
                    @"samplePhotos": @[]
                });
            });
            return;
        }

        // Fetch PHAssets
        PHFetchOptions *options = [[PHFetchOptions alloc] init];
        NSDate *sinceDate = [NSDate dateWithTimeIntervalSinceNow:-(sinceDays * 86400.0)];
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d AND creationDate >= %@",
                            PHAssetMediaTypeImage, sinceDate];
        options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        options.fetchLimit = limit;

        PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithOptions:options];

        // Process
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSMutableDictionary<NSString *, NSNumber *> *dayOfWeekCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *hourOfDayCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *locationGrid = [NSMutableDictionary dictionary]; // "lat,lon" -> count
        NSMutableDictionary<NSString *, NSArray *> *locationCoords = [NSMutableDictionary dictionary]; // "lat,lon" -> @[lat, lon]
        NSInteger totalPhotos = assets.count;
        __block NSInteger photosWithLocation = 0;

        // Collect all asset data
        NSMutableArray<NSDictionary *> *allAssetData = [NSMutableArray array];

        [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
            NSDate *date = asset.creationDate;
            if (!date) return;

            // Day of week
            NSDateComponents *comps = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour) fromDate:date];
            NSString *dayName = dayNameFromWeekday(comps.weekday);
            dayOfWeekCounts[dayName] = @(dayOfWeekCounts[dayName].integerValue + 1);

            // Hour of day
            NSString *hourKey = [NSString stringWithFormat:@"%ld", (long)comps.hour];
            hourOfDayCounts[hourKey] = @(hourOfDayCounts[hourKey].integerValue + 1);

            // Location
            CLLocation *loc = asset.location;
            BOOL hasLoc = (loc != nil);
            if (hasLoc) {
                photosWithLocation++;
                // Grid cell: round to 2 decimal places (~1km)
                double gridLat = round(loc.coordinate.latitude * 100.0) / 100.0;
                double gridLon = round(loc.coordinate.longitude * 100.0) / 100.0;
                NSString *gridKey = [NSString stringWithFormat:@"%.2f,%.2f", gridLat, gridLon];
                locationGrid[gridKey] = @(locationGrid[gridKey].integerValue + 1);
                locationCoords[gridKey] = @[@(gridLat), @(gridLon)];
            }

            // Store for sampling
            NSMutableDictionary *assetDict = [NSMutableDictionary dictionary];
            assetDict[@"timestamp"] = @((long long)([date timeIntervalSince1970] * 1000.0));
            assetDict[@"hasLocation"] = @(hasLoc);
            if (hasLoc) {
                assetDict[@"lat"] = @(loc.coordinate.latitude);
                assetDict[@"lon"] = @(loc.coordinate.longitude);
            } else {
                assetDict[@"lat"] = [NSNull null];
                assetDict[@"lon"] = [NSNull null];
            }
            [allAssetData addObject:assetDict];
        }];

        // Top 5 location grid cells
        NSArray<NSString *> *sortedGridKeys = [locationGrid keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [b compare:a]; // Descending
        }];
        NSMutableArray<NSDictionary *> *topLocations = [NSMutableArray array];
        for (NSUInteger i = 0; i < MIN(5, sortedGridKeys.count); i++) {
            NSString *key = sortedGridKeys[i];
            NSArray *coords = locationCoords[key];
            [topLocations addObject:@{
                @"lat": coords[0],
                @"lon": coords[1],
                @"count": locationGrid[key]
            }];
        }

        // Sample photos: up to 10 representative (every Nth)
        NSMutableArray<NSDictionary *> *samplePhotos = [NSMutableArray array];
        if (allAssetData.count > 0) {
            NSUInteger step = MAX(1, allAssetData.count / 10);
            for (NSUInteger i = 0; i < allAssetData.count && samplePhotos.count < 10; i += step) {
                [samplePhotos addObject:allAssetData[i]];
            }
        }

        NSDictionary *response = @{
            @"totalPhotos": @(totalPhotos),
            @"dayOfWeekCounts": dayOfWeekCounts,
            @"hourOfDayCounts": hourOfDayCounts,
            @"topLocations": topLocations,
            @"photosWithLocation": @(photosWithLocation),
            @"samplePhotos": samplePhotos
        };

        dispatch_async(dispatch_get_main_queue(), ^{
            result(response);
        });
    });
}

#pragma mark - Calendar Insights

/// Fetch calendar events and return lightly processed summaries.
- (void)handleGetCalendarInsights:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;
    int sinceDays = args[@"sinceDays"] ? [args[@"sinceDays"] intValue] : 30;
    int untilDays = args[@"untilDays"] ? [args[@"untilDays"] intValue] : 0;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        EKEventStore *store = [[EKEventStore alloc] init];

        // Check permission
        EKAuthorizationStatus ekStatus = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
        BOOL hasAccess = NO;
        if (@available(iOS 17.0, *)) {
            hasAccess = (ekStatus == EKAuthorizationStatusFullAccess);
        } else {
            hasAccess = (ekStatus == EKAuthorizationStatusAuthorized);
        }

        if (!hasAccess) {
            dispatch_async(dispatch_get_main_queue(), ^{
                result(@{
                    @"totalEvents": @(0),
                    @"dayOfWeekCounts": @{},
                    @"hourOfDayCounts": @{},
                    @"meetingMinutesPerWeekday": @{},
                    @"averageDurationMinutes": @(0),
                    @"sampleEvents": @[]
                });
            });
            return;
        }

        // Date range
        NSDate *startDate = [NSDate dateWithTimeIntervalSinceNow:-(sinceDays * 86400.0)];
        NSDate *endDate;
        if (untilDays > 0) {
            endDate = [NSDate dateWithTimeIntervalSinceNow:(untilDays * 86400.0)];
        } else {
            endDate = [NSDate date];
        }

        NSPredicate *predicate = [store predicateForEventsWithStartDate:startDate endDate:endDate calendars:nil];
        NSArray<EKEvent *> *events = [store eventsMatchingPredicate:predicate];

        if (!events || events.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                result(@{
                    @"totalEvents": @(0),
                    @"dayOfWeekCounts": @{},
                    @"hourOfDayCounts": @{},
                    @"meetingMinutesPerWeekday": @{},
                    @"averageDurationMinutes": @(0),
                    @"sampleEvents": @[]
                });
            });
            return;
        }

        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSMutableDictionary<NSString *, NSNumber *> *dayOfWeekCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *hourOfDayCounts = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSString *, NSNumber *> *meetingMinutesPerWeekday = [NSMutableDictionary dictionary];
        double totalDurationMinutes = 0.0;
        NSInteger totalEvents = events.count;

        NSMutableArray<NSDictionary *> *allEventData = [NSMutableArray array];

        for (EKEvent *event in events) {
            if (!event.startDate || !event.endDate) continue;

            NSDateComponents *comps = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour) fromDate:event.startDate];
            NSString *dayName = dayNameFromWeekday(comps.weekday);

            // Day of week count
            dayOfWeekCounts[dayName] = @(dayOfWeekCounts[dayName].integerValue + 1);

            // Hour of day count
            NSString *hourKey = [NSString stringWithFormat:@"%ld", (long)comps.hour];
            hourOfDayCounts[hourKey] = @(hourOfDayCounts[hourKey].integerValue + 1);

            // Duration in minutes
            double durationMinutes = [event.endDate timeIntervalSinceDate:event.startDate] / 60.0;
            if (durationMinutes < 0) durationMinutes = 0;
            totalDurationMinutes += durationMinutes;

            // Meeting minutes per weekday
            meetingMinutesPerWeekday[dayName] = @(meetingMinutesPerWeekday[dayName].doubleValue + durationMinutes);

            // Truncate title to 50 chars for privacy
            NSString *title = event.title ?: @"(No title)";
            if (title.length > 50) {
                title = [[title substringToIndex:50] stringByAppendingString:@"..."];
            }

            [allEventData addObject:@{
                @"startTimestamp": @((long long)([event.startDate timeIntervalSince1970] * 1000.0)),
                @"endTimestamp": @((long long)([event.endDate timeIntervalSince1970] * 1000.0)),
                @"title": title,
                @"durationMinutes": @((int)round(durationMinutes))
            }];
        }

        double averageDuration = totalEvents > 0 ? totalDurationMinutes / totalEvents : 0;

        // Sample events: up to 10 representative (every Nth)
        NSMutableArray<NSDictionary *> *sampleEvents = [NSMutableArray array];
        if (allEventData.count > 0) {
            NSUInteger step = MAX(1, allEventData.count / 10);
            for (NSUInteger i = 0; i < allEventData.count && sampleEvents.count < 10; i += step) {
                [sampleEvents addObject:allEventData[i]];
            }
        }

        NSDictionary *response = @{
            @"totalEvents": @(totalEvents),
            @"dayOfWeekCounts": dayOfWeekCounts,
            @"hourOfDayCounts": hourOfDayCounts,
            @"meetingMinutesPerWeekday": meetingMinutesPerWeekday,
            @"averageDurationMinutes": @((int)round(averageDuration)),
            @"sampleEvents": sampleEvents
        };

        dispatch_async(dispatch_get_main_queue(), ^{
            result(response);
        });
    });
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    // Cleanup handled by ARC and notification center observers
}

@end
