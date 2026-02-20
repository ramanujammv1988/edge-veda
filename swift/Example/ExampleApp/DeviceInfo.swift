//
//  DeviceInfo.swift
//  ExampleApp
//
//  Device information utilities
//

import Foundation
import UIKit

struct DeviceInfo {
    let modelName: String
    let chipName: String
    let totalMemoryGB: Double
    let hasNeuralEngine: Bool
    
    static func current() -> DeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        let modelName = Self.deviceModel(from: identifier)
        let chipName = Self.chipName(from: identifier)
        let totalMemory = Self.getTotalMemory()
        let hasNeuralEngine = Self.hasNeuralEngine(from: identifier)
        
        return DeviceInfo(
            modelName: modelName,
            chipName: chipName,
            totalMemoryGB: totalMemory,
            hasNeuralEngine: hasNeuralEngine
        )
    }
    
    private static func deviceModel(from identifier: String) -> String {
        // Map common device identifiers to user-friendly names
        let models: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
        ]
        
        return models[identifier] ?? identifier
    }
    
    private static func chipName(from identifier: String) -> String {
        // Determine chip based on device
        if identifier.contains("iPhone15") || identifier.contains("iPhone16") || identifier.contains("iPhone17") {
            if identifier.hasSuffix("1") || identifier.hasSuffix("2") {
                return "A17 Pro" // Pro models
            }
            return "A16 Bionic"
        } else if identifier.contains("iPhone14") {
            return "A15 Bionic"
        } else if identifier.contains("iPhone13") {
            return "A14 Bionic"
        }
        
        return "Apple Silicon"
    }
    
    private static func getTotalMemory() -> Double {
        let totalMemoryBytes = Double(ProcessInfo.processInfo.physicalMemory)
        return totalMemoryBytes / 1_073_741_824 // Convert to GB
    }
    
    private static func hasNeuralEngine(from identifier: String) -> Bool {
        // All modern iPhones (A11+) have Neural Engine
        // For simplicity, assume true for iPhone 8 and later
        return true
    }

    // MARK: - Static Accessors

    static var modelName: String     { current().modelName }
    static var chipName: String      { current().chipName }
    static var memoryString: String  { String(format: "%.1f GB", current().totalMemoryGB) }
    static var hasNeuralEngine: Bool { current().hasNeuralEngine }
}