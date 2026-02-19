import Cocoa
import FlutterMacOS
import AVFoundation
import Photos
import EventKit
import IOKit.ps

// MARK: - ThermalStreamHandler

/// Stream handler for macOS thermal state change push notifications.
/// On macOS 12+, uses ProcessInfo.thermalStateDidChangeNotification.
/// On macOS 11, falls back to returning .nominal (0).
class EVThermalStreamHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        if #available(macOS 12.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(thermalStateDidChange),
                name: ProcessInfo.thermalStateDidChangeNotification,
                object: nil
            )
        }

        sendCurrentThermalState()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NotificationCenter.default.removeObserver(self)
        eventSink = nil
        return nil
    }

    @objc private func thermalStateDidChange(_ notification: Notification) {
        sendCurrentThermalState()
    }

    private func sendCurrentThermalState() {
        guard let eventSink = eventSink else { return }

        let state: Int
        if #available(macOS 12.0, *) {
            state = Int(ProcessInfo.processInfo.thermalState.rawValue)
        } else {
            state = 0 // .nominal fallback for macOS 11
        }

        let timestampMs = Date().timeIntervalSince1970 * 1000.0

        DispatchQueue.main.async {
            eventSink([
                "thermalState": state,
                "timestamp": timestampMs,
            ])
        }
    }
}

// MARK: - AudioCaptureStreamHandler

/// Stream handler for microphone audio capture via AVAudioEngine.
/// Delivers 16kHz mono float32 PCM samples via EventChannel.
class EVAudioCaptureHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var audioEngine: AVAudioEngine?

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        do {
            let engine = AVAudioEngine()
            self.audioEngine = engine
            let inputNode = engine.inputNode

            let nativeFormat = inputNode.outputFormat(forBus: 0)

            // Defensive check: handle no audio input gracefully
            guard nativeFormat.sampleRate >= 1.0, nativeFormat.channelCount > 0 else {
                self.audioEngine = nil
                return FlutterError(
                    code: "AUDIO_FORMAT_UNAVAILABLE",
                    message: "Microphone audio format is invalid (no audio input available)",
                    details: "sampleRate=\(nativeFormat.sampleRate) channels=\(nativeFormat.channelCount)"
                )
            }

            // Target format: 16kHz mono float32 (what whisper.cpp expects)
            guard let whisperFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000.0,
                channels: 1,
                interleaved: false
            ) else {
                self.audioEngine = nil
                return FlutterError(
                    code: "AUDIO_FORMAT_FAILED",
                    message: "Failed to create whisper audio format",
                    details: nil
                )
            }

            guard let converter = AVAudioConverter(from: nativeFormat, to: whisperFormat) else {
                self.audioEngine = nil
                return FlutterError(
                    code: "AUDIO_CONVERTER_FAILED",
                    message: "Failed to create audio format converter",
                    details: nil
                )
            }

            // Buffer size in native sample rate frames (~300ms worth)
            let tapBufferSize = AVAudioFrameCount(nativeFormat.sampleRate * 0.3)

            inputNode.installTap(onBus: 0, bufferSize: tapBufferSize, format: nativeFormat) { [weak self] buffer, _ in
                guard let self = self else { return }

                let ratio = 16000.0 / nativeFormat.sampleRate
                let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1

                guard let converted = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outputCapacity) else {
                    return
                }

                converter.reset()

                var inputConsumed = false
                var convError: NSError?
                let status = converter.convert(to: converted, error: &convError) { _, outStatus in
                    if inputConsumed {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    inputConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData, convError == nil,
                   let channelData = converted.floatChannelData?[0] {
                    let frameLength = Int(converted.frameLength)
                    let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
                    let typedData = FlutterStandardTypedData(float32: data)

                    DispatchQueue.main.async {
                        self.eventSink?(typedData)
                    }
                }
            }

            try engine.start()
            return nil
        } catch {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            return FlutterError(
                code: "AUDIO_ERROR",
                message: error.localizedDescription,
                details: nil
            )
        }
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        eventSink = nil
        return nil
    }
}

// MARK: - EdgeVedaPlugin

public class EdgeVedaPlugin: NSObject, FlutterPlugin {

    public static func register(with registrar: FlutterPluginRegistrar) {
        // MethodChannel for on-demand telemetry polling
        let methodChannel = FlutterMethodChannel(
            name: "com.edgeveda.edge_veda/telemetry",
            binaryMessenger: registrar.messenger
        )

        let instance = EdgeVedaPlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        // EventChannel for push thermal state notifications
        let thermalChannel = FlutterEventChannel(
            name: "com.edgeveda.edge_veda/thermal",
            binaryMessenger: registrar.messenger
        )
        thermalChannel.setStreamHandler(EVThermalStreamHandler())

        // EventChannel for microphone audio capture (16kHz mono float32 PCM)
        let audioChannel = FlutterEventChannel(
            name: "com.edgeveda.edge_veda/audio_capture",
            binaryMessenger: registrar.messenger
        )
        audioChannel.setStreamHandler(EVAudioCaptureHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getThermalState":
            handleGetThermalState(result)
        case "getBatteryLevel":
            handleGetBatteryLevel(result)
        case "getBatteryState":
            handleGetBatteryState(result)
        case "getMemoryRSS":
            handleGetMemoryRSS(result)
        case "getAvailableMemory":
            handleGetAvailableMemory(result)
        case "isLowPowerMode":
            handleIsLowPowerMode(result)
        case "requestMicrophonePermission":
            handleRequestMicrophonePermission(result)
        case "shareFile":
            handleShareFile(call, result: result)
        case "checkDetectivePermissions":
            handleCheckDetectivePermissions(result)
        case "requestDetectivePermissions":
            handleRequestDetectivePermissions(result)
        case "getPhotoInsights":
            handleGetPhotoInsights(call, result: result)
        case "getCalendarInsights":
            handleGetCalendarInsights(call, result: result)
        case "getFreeDiskSpace":
            handleGetFreeDiskSpace(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Thermal

    /// Returns thermal state as int: 0=nominal, 1=fair, 2=serious, 3=critical
    private func handleGetThermalState(_ result: FlutterResult) {
        if #available(macOS 12.0, *) {
            result(Int(ProcessInfo.processInfo.thermalState.rawValue))
        } else {
            result(0) // nominal fallback
        }
    }

    // MARK: - Battery (IOKit)

    /// Returns battery level as double: 0.0 to 1.0, or -1.0 if no battery (desktop Mac)
    private func handleGetBatteryLevel(_ result: FlutterResult) {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(powerInfo, firstSource)?.takeUnretainedValue() as? [String: Any],
              let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
              let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
              maxCapacity > 0 else {
            result(-1.0) // No battery (desktop Mac)
            return
        }

        let level = Double(currentCapacity) / Double(maxCapacity)
        result(level)
    }

    /// Returns battery state as int: 0=unknown, 1=unplugged, 2=charging, 3=full
    private func handleGetBatteryState(_ result: FlutterResult) {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef],
              let firstSource = sources.first,
              let description = IOPSGetPowerSourceDescription(powerInfo, firstSource)?.takeUnretainedValue() as? [String: Any] else {
            result(0) // unknown
            return
        }

        let powerSource = description[kIOPSPowerSourceStateKey as String] as? String
        let isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey as String] as? Bool ?? false

        if isCharged {
            result(3) // full
        } else if isCharging {
            result(2) // charging
        } else if powerSource == kIOPSBatteryPowerValue as String {
            result(1) // unplugged (on battery)
        } else {
            result(0) // unknown
        }
    }

    // MARK: - Memory

    /// Returns process RSS (resident set size) in bytes via task_info.
    private func handleGetMemoryRSS(_ result: FlutterResult) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rawPtr, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            result(Int64(info.resident_size))
        } else {
            result(0)
        }
    }

    /// Returns available memory in bytes.
    private func handleGetAvailableMemory(_ result: FlutterResult) {
        if #available(macOS 12.0, *) {
            result(Int64(os_proc_available_memory()))
        } else {
            // Fallback: use host_statistics64
            var vmStats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<natural_t>.size)

            let kerr = withUnsafeMutablePointer(to: &vmStats) { vmStatsPtr in
                vmStatsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPtr in
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, rawPtr, &count)
                }
            }

            if kerr == KERN_SUCCESS {
                let pageSize = Int64(vm_kernel_page_size)
                let free = Int64(vmStats.free_count) * pageSize
                let inactive = Int64(vmStats.inactive_count) * pageSize
                result(free + inactive)
            } else {
                result(Int64(0))
            }
        }
    }

    // MARK: - Storage

    /// Returns free disk space in bytes.
    private func handleGetFreeDiskSpace(_ result: FlutterResult) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                result(freeSpace)
            } else {
                result(Int64(-1))
            }
        } catch {
            result(Int64(-1))
        }
    }

    // MARK: - Power

    /// Returns whether Low Power Mode is enabled (macOS 12+).
    private func handleIsLowPowerMode(_ result: FlutterResult) {
        if #available(macOS 12.0, *) {
            result(ProcessInfo.processInfo.isLowPowerModeEnabled)
        } else {
            result(false)
        }
    }

    // MARK: - Microphone Permission

    /// Request microphone recording permission from the user.
    private func handleRequestMicrophonePermission(_ result: @escaping FlutterResult) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                result(granted)
            }
        }
    }

    // MARK: - Share

    /// Present macOS sharing service for a file at the given path.
    private func handleShareFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARG", message: "Missing 'path' argument", details: nil))
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            result(FlutterError(code: "FILE_NOT_FOUND", message: "File not found", details: filePath))
            return
        }

        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow,
                  let contentView = window.contentView else {
                result(FlutterError(code: "NO_VIEW", message: "No key window available", details: nil))
                return
            }

            let picker = NSSharingServicePicker(items: [fileURL])
            let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 0, height: 0)
            picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
            result(true)
        }
    }

    // MARK: - Detective Permissions

    /// Check current photo and calendar permission status without prompting.
    private func handleCheckDetectivePermissions(_ result: @escaping FlutterResult) {
        DispatchQueue.global().async {
            // Check Photos permission
            let photosStatus: String
            let phStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch phStatus {
            case .authorized:
                photosStatus = "granted"
            case .limited:
                photosStatus = "limited"
            case .denied, .restricted:
                photosStatus = "denied"
            case .notDetermined:
                photosStatus = "notDetermined"
            @unknown default:
                photosStatus = "notDetermined"
            }

            // Check Calendar permission
            let calendarStatus: String
            let ekStatus = EKEventStore.authorizationStatus(for: .event)
            switch ekStatus {
            case .authorized:
                calendarStatus = "granted"
            case .fullAccess:
                calendarStatus = "granted"
            case .denied, .restricted:
                calendarStatus = "denied"
            case .notDetermined:
                calendarStatus = "notDetermined"
            case .writeOnly:
                calendarStatus = "denied"
            @unknown default:
                calendarStatus = "notDetermined"
            }

            DispatchQueue.main.async {
                result(["photos": photosStatus, "calendar": calendarStatus])
            }
        }
    }

    /// Request photo and calendar permissions sequentially.
    /// Both PHPhotoLibrary and EKEventStore permission APIs must be called
    /// on the main thread because they may synchronously trigger system UI.
    private func handleRequestDetectivePermissions(_ result: @escaping FlutterResult) {
        // Step 1: Request Photos permission (must be on main thread)
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { phStatus in
            let photosStatus: String
            switch phStatus {
            case .authorized:
                photosStatus = "granted"
            case .limited:
                photosStatus = "limited"
            default:
                photosStatus = "denied"
            }

            // Step 2: Request Calendar permission (must be on main thread)
            DispatchQueue.main.async {
                let eventStore = EKEventStore()

                if #available(macOS 14.0, *) {
                    eventStore.requestFullAccessToEvents { granted, _ in
                        let calendarStatus = granted ? "granted" : "denied"
                        DispatchQueue.main.async {
                            result(["photos": photosStatus, "calendar": calendarStatus])
                        }
                    }
                } else {
                    eventStore.requestAccess(to: .event) { granted, _ in
                        let calendarStatus = granted ? "granted" : "denied"
                        DispatchQueue.main.async {
                            result(["photos": photosStatus, "calendar": calendarStatus])
                        }
                    }
                }
            }
        }
    }

    // MARK: - Photo Insights

    private static let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static func dayName(from weekday: Int) -> String {
        guard weekday >= 1, weekday <= 7 else { return "Unknown" }
        return dayNames[weekday - 1]
    }

    /// Fetch photo metadata and return lightly processed summaries.
    private func handleGetPhotoInsights(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let limit = args["limit"] as? Int ?? 500
        let sinceDays = args["sinceDays"] as? Int ?? 30

        DispatchQueue.global().async {
            // Check permission
            let phStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            let hasAccess = (phStatus == .authorized || phStatus == .limited)

            if !hasAccess {
                DispatchQueue.main.async {
                    result([
                        "totalPhotos": 0,
                        "dayOfWeekCounts": [:] as [String: Any],
                        "hourOfDayCounts": [:] as [String: Any],
                        "topLocations": [] as [[String: Any]],
                        "photosWithLocation": 0,
                        "samplePhotos": [] as [[String: Any]],
                    ])
                }
                return
            }

            // Fetch PHAssets
            let options = PHFetchOptions()
            let sinceDate = Date(timeIntervalSinceNow: -Double(sinceDays * 86400))
            options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@",
                                            PHAssetMediaType.image.rawValue, sinceDate as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit

            let assets = PHAsset.fetchAssets(with: options)

            let calendar = Calendar.current
            var dayOfWeekCounts: [String: Int] = [:]
            var hourOfDayCounts: [String: Int] = [:]
            var locationGrid: [String: Int] = [:]
            var locationCoords: [String: [Double]] = [:]
            var photosWithLocation = 0
            var allAssetData: [[String: Any]] = []

            assets.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate else { return }

                let comps = calendar.dateComponents([.weekday, .hour], from: date)
                let dayName = EdgeVedaPlugin.dayName(from: comps.weekday ?? 1)
                dayOfWeekCounts[dayName, default: 0] += 1

                let hourKey = "\(comps.hour ?? 0)"
                hourOfDayCounts[hourKey, default: 0] += 1

                let hasLoc = asset.location != nil
                if let loc = asset.location {
                    photosWithLocation += 1
                    let gridLat = (loc.coordinate.latitude * 100.0).rounded() / 100.0
                    let gridLon = (loc.coordinate.longitude * 100.0).rounded() / 100.0
                    let gridKey = String(format: "%.2f,%.2f", gridLat, gridLon)
                    locationGrid[gridKey, default: 0] += 1
                    locationCoords[gridKey] = [gridLat, gridLon]
                }

                var assetDict: [String: Any] = [
                    "timestamp": Int64(date.timeIntervalSince1970 * 1000.0),
                    "hasLocation": hasLoc,
                ]
                if let loc = asset.location {
                    assetDict["lat"] = loc.coordinate.latitude
                    assetDict["lon"] = loc.coordinate.longitude
                } else {
                    assetDict["lat"] = NSNull()
                    assetDict["lon"] = NSNull()
                }
                allAssetData.append(assetDict)
            }

            // Top 5 location grid cells
            let sortedGridKeys = locationGrid.sorted { $0.value > $1.value }.prefix(5)
            var topLocations: [[String: Any]] = []
            for (key, count) in sortedGridKeys {
                if let coords = locationCoords[key] {
                    topLocations.append([
                        "lat": coords[0],
                        "lon": coords[1],
                        "count": count,
                    ])
                }
            }

            // Sample photos: up to 10 representative (every Nth)
            var samplePhotos: [[String: Any]] = []
            if !allAssetData.isEmpty {
                let step = max(1, allAssetData.count / 10)
                var i = 0
                while i < allAssetData.count, samplePhotos.count < 10 {
                    samplePhotos.append(allAssetData[i])
                    i += step
                }
            }

            let response: [String: Any] = [
                "totalPhotos": assets.count,
                "dayOfWeekCounts": dayOfWeekCounts,
                "hourOfDayCounts": hourOfDayCounts,
                "topLocations": topLocations,
                "photosWithLocation": photosWithLocation,
                "samplePhotos": samplePhotos,
            ]

            DispatchQueue.main.async {
                result(response)
            }
        }
    }

    // MARK: - Calendar Insights

    /// Fetch calendar events and return lightly processed summaries.
    private func handleGetCalendarInsights(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let sinceDays = args["sinceDays"] as? Int ?? 30
        let untilDays = args["untilDays"] as? Int ?? 0

        DispatchQueue.global().async {
            let store = EKEventStore()

            let ekStatus = EKEventStore.authorizationStatus(for: .event)
            var hasAccess = false
            if #available(macOS 14.0, *) {
                hasAccess = (ekStatus == .fullAccess)
            } else {
                hasAccess = (ekStatus == .authorized)
            }

            let emptyResponse: [String: Any] = [
                "totalEvents": 0,
                "dayOfWeekCounts": [:] as [String: Any],
                "hourOfDayCounts": [:] as [String: Any],
                "meetingMinutesPerWeekday": [:] as [String: Any],
                "averageDurationMinutes": 0,
                "sampleEvents": [] as [[String: Any]],
            ]

            if !hasAccess {
                DispatchQueue.main.async { result(emptyResponse) }
                return
            }

            let startDate = Date(timeIntervalSinceNow: -Double(sinceDays * 86400))
            let endDate: Date
            if untilDays > 0 {
                endDate = Date(timeIntervalSinceNow: Double(untilDays * 86400))
            } else {
                endDate = Date()
            }

            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let events = store.events(matching: predicate)

            if events.isEmpty {
                DispatchQueue.main.async { result(emptyResponse) }
                return
            }

            let calendar = Calendar.current
            var dayOfWeekCounts: [String: Int] = [:]
            var hourOfDayCounts: [String: Int] = [:]
            var meetingMinutesPerWeekday: [String: Double] = [:]
            var totalDurationMinutes = 0.0
            var allEventData: [[String: Any]] = []

            for event in events {
                guard let startDate = event.startDate, let endDate = event.endDate else { continue }

                let comps = calendar.dateComponents([.weekday, .hour], from: startDate)
                let dayName = EdgeVedaPlugin.dayName(from: comps.weekday ?? 1)

                dayOfWeekCounts[dayName, default: 0] += 1

                let hourKey = "\(comps.hour ?? 0)"
                hourOfDayCounts[hourKey, default: 0] += 1

                var durationMinutes = endDate.timeIntervalSince(startDate) / 60.0
                if durationMinutes < 0 { durationMinutes = 0 }
                totalDurationMinutes += durationMinutes

                meetingMinutesPerWeekday[dayName, default: 0] += durationMinutes

                var title = event.title ?? "(No title)"
                if title.count > 50 {
                    title = String(title.prefix(50)) + "..."
                }

                allEventData.append([
                    "startTimestamp": Int64(startDate.timeIntervalSince1970 * 1000.0),
                    "endTimestamp": Int64(endDate.timeIntervalSince1970 * 1000.0),
                    "title": title,
                    "durationMinutes": Int(durationMinutes.rounded()),
                ])
            }

            let averageDuration = events.count > 0 ? totalDurationMinutes / Double(events.count) : 0

            // Sample events: up to 10 representative (every Nth)
            var sampleEvents: [[String: Any]] = []
            if !allEventData.isEmpty {
                let step = max(1, allEventData.count / 10)
                var i = 0
                while i < allEventData.count, sampleEvents.count < 10 {
                    sampleEvents.append(allEventData[i])
                    i += step
                }
            }

            let response: [String: Any] = [
                "totalEvents": events.count,
                "dayOfWeekCounts": dayOfWeekCounts,
                "hourOfDayCounts": hourOfDayCounts,
                "meetingMinutesPerWeekday": meetingMinutesPerWeekday,
                "averageDurationMinutes": Int(averageDuration.rounded()),
                "sampleEvents": sampleEvents,
            ]

            DispatchQueue.main.async {
                result(response)
            }
        }
    }

    // MARK: - Cleanup

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Cleanup handled by ARC and notification center observers
    }
}
