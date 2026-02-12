import Foundation

/// Maps C core `ev_error_*` integer codes to Swift `EdgeVedaError` cases.
///
/// The native C engine returns integer error codes through the FFI boundary.
/// This enum provides a type-safe mapping from those codes to rich Swift errors.
///
/// ## Usage
/// ```swift
/// let code = NativeErrorCode(rawValue: resultCode) ?? .unknown
/// if let error = code.toEdgeVedaError() {
///     throw error
/// }
/// ```
public enum NativeErrorCode: Int32, Sendable {
    /// Operation completed successfully (no error)
    case ok = 0

    /// Model file was not found at the specified path
    case modelNotFound = 1

    /// Model failed to load (corrupt file, unsupported format, etc.)
    case modelLoadFailed = 2

    /// System ran out of memory during operation
    case outOfMemory = 3

    /// Prompt exceeded the model's context window size
    case contextOverflow = 4

    /// An invalid parameter was passed to the engine
    case invalidParameter = 5

    /// Text generation failed mid-operation
    case generationFailed = 6

    /// Operation was cancelled by the user
    case cancelled = 7

    /// Unknown or unmapped error code
    case unknown = -1

    /// Initialize from a raw C error code, defaulting to `.unknown` for unmapped values.
    public static func from(code: Int32) -> NativeErrorCode {
        return NativeErrorCode(rawValue: code) ?? .unknown
    }

    /// Convert this native error code to an `EdgeVedaError`.
    ///
    /// Returns `nil` for `.ok` since no error occurred.
    ///
    /// - Parameter context: Optional additional context string to include in the error message.
    /// - Returns: The corresponding `EdgeVedaError`, or `nil` if the code is `.ok`.
    public func toEdgeVedaError(context: String? = nil) -> EdgeVedaError? {
        let ctx = context ?? "Native engine error"

        switch self {
        case .ok:
            return nil

        case .modelNotFound:
            return .modelNotFound(path: ctx)

        case .modelLoadFailed:
            return .loadFailed(reason: ctx)

        case .outOfMemory:
            return .outOfMemory

        case .contextOverflow:
            return .contextOverflow

        case .invalidParameter:
            return .invalidParameter(name: "native", value: ctx)

        case .generationFailed:
            return .generationFailed(reason: ctx)

        case .cancelled:
            return .cancellation

        case .unknown:
            return .unknown(message: ctx)
        }
    }

    /// Throw the corresponding `EdgeVedaError` if this code is not `.ok`.
    ///
    /// - Parameter context: Optional context string for the error message.
    /// - Throws: `EdgeVedaError` if the code represents an error.
    public func throwIfError(context: String? = nil) throws {
        if let error = toEdgeVedaError(context: context) {
            throw error
        }
    }
}