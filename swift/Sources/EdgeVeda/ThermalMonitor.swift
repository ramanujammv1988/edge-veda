import Foundation

#if os(iOS) || os(macOS)
import os.log
#endif

/// Monitors device thermal state for budget enforcement.
///
/// Tracks thermal pressure levels (0-3) using ProcessInfo.thermalState API.
/// Thermal monitoring helps prevent device overheating and throttling.
///
/// Thermal Levels:
/// - 0: Nominal (normal operation)
/// - 1: Fair (slight thermal pressure)
/// - 2: Serious (significant thermal pressure, recommend throttling)
/// - 3: Critical (severe thermal pressure, must throttle)
/// - -1: Unavailable (platform doesn't support thermal monitoring)
///
/// Example:
/// ```swift
/// let monitor = ThermalMonitor()
/// let level = await monitor.currentLevel
/// if level >= 2 {
///     // Throttle inference workload
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
actor ThermalMonitor {
    #if os(iOS) || os(macOS)
    private var currentState: ProcessInfo.ThermalState = .nominal
    private let logger = Logger(subsystem: "com.edgeveda.sdk", category: "ThermalMonitor")
    // Stored so it can be removed in deinit; discarding this token leaks the observer block.
    private var thermalObserver: NSObjectProtocol?
    #else
    private var currentLevel: Int = -1
    #endif
    
    private var stateChangeListeners: [UUID: @Sendable (Int) -> Void] = [:]
    
    // MARK: - Initialization
    
    init() {
        #if os(iOS) || os(macOS)
        // Get initial state
        currentState = ProcessInfo.processInfo.thermalState
        
        // Register for thermal state notifications.
        // Store the returned token so the observer can be removed in deinit;
        // without this the closure block stays in NotificationCenter indefinitely.
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleThermalStateChange()
            }
        }
        
        logger.info("ThermalMonitor initialized. Current state: \(self.currentState.rawValue)")
        #endif
    }
    
    // MARK: - Public Properties
    
    /// Current thermal level (0-3, or -1 if unavailable).
    var currentLevel: Int {
        #if os(iOS) || os(macOS)
        return thermalStateToLevel(currentState)
        #else
        return -1
        #endif
    }
    
    /// Human-readable thermal state name.
    var currentStateName: String {
        #if os(iOS) || os(macOS)
        return thermalStateName(currentState)
        #else
        return "unavailable"
        #endif
    }
    
    /// Whether thermal monitoring is supported on this platform.
    nonisolated var isSupported: Bool {
        #if os(iOS) || os(macOS)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Register a callback for thermal state changes.
    ///
    /// - Parameter callback: Called when thermal state changes
    /// - Returns: UUID to use for removing the listener
    @discardableResult
    func onThermalStateChange(
        _ callback: @escaping @Sendable (Int) -> Void
    ) -> UUID {
        let id = UUID()
        stateChangeListeners[id] = callback
        return id
    }
    
    /// Remove a thermal state change listener.
    func removeListener(_ id: UUID) {
        stateChangeListeners.removeValue(forKey: id)
    }
    
    /// Check if current thermal state requires throttling.
    ///
    /// Returns true if thermal level is 2 (serious) or higher.
    var shouldThrottle: Bool {
        return currentLevel >= 2
    }
    
    /// Check if current thermal state is critical.
    ///
    /// Returns true if thermal level is 3 (critical).
    var isCritical: Bool {
        return currentLevel >= 3
    }
    
    // MARK: - Private Methods
    
    #if os(iOS) || os(macOS)
    private func handleThermalStateChange() {
        let previousState = currentState
        currentState = ProcessInfo.processInfo.thermalState
        
        let previousLevel = thermalStateToLevel(previousState)
        let newLevel = thermalStateToLevel(currentState)
        
        if previousLevel != newLevel {
            logger.info("Thermal state changed: \(self.thermalStateName(previousState)) → \(self.thermalStateName(self.currentState))")
            
            // Notify listeners
            for listener in stateChangeListeners.values {
                listener(newLevel)
            }
        }
    }
    
    private func thermalStateToLevel(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        @unknown default:
            return -1
        }
    }
    
    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
    #endif

    // MARK: - Lifecycle

    nonisolated deinit {
        #if os(iOS) || os(macOS)
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }
}