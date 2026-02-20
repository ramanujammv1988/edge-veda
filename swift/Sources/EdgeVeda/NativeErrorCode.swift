import Foundation

/// Maps C core `ev_error_*` integer codes to Swift `EdgeVedaError` cases.
///
/// The native C engine returns integer error codes through the FFI boundary.
/// This enum provides a type-safe mapping from those codes to rich Swift errors.
///
/// Raw values match the `ev_error_t` enum defined in `edge_veda.h` exactly.
/// Previous versions used positive codes (1–7) which never matched the C API's
/// negative values, causing all errors to map to `.unknown`.
///
/// ## Usage
/// ```swift
/// let code = NativeErrorCode(rawValue: resultCode) ?? .unknown
/// if let error = code.toEdgeVedaError() {
///     throw error
/// }
/// ```
public enum NativeErrorCode: Int32, Sendable {
    /// Operation completed successfully (no error). EV_SUCCESS = 0
    case ok = 0

    /// Invalid parameter provided. EV_ERROR_INVALID_PARAM = -1
    case invalidParameter = -1

    /// Out of memory. EV_ERROR_OUT_OF_MEMORY = -2
    case outOfMemory = -2

    /// Failed to load model. EV_ERROR_MODEL_LOAD_FAILED = -3
    case modelLoadFailed = -3

    /// Failed to initialize backend. EV_ERROR_BACKEND_INIT_FAILED = -4
    case backendInitFailed = -4

    /// Inference operation failed. EV_ERROR_INFERENCE_FAILED = -5
    case inferenceFailed = -5

    /// Invalid context handle. EV_ERROR_CONTEXT_INVALID = -6
    case contextInvalid = -6

    /// Stream has ended (not an error — used as a sentinel). EV_ERROR_STREAM_ENDED = -7
    case streamEnded = -7

    /// Feature not implemented. EV_ERROR_NOT_IMPLEMENTED = -8
    case notImplemented = -8

    /// Memory limit exceeded. EV_ERROR_MEMORY_LIMIT_EXCEEDED = -9
    case memoryLimitExceeded = -9

    /// Backend not supported on this platform. EV_ERROR_UNSUPPORTED_BACKEND = -10
    case unsupportedBackend = -10

    /// Unknown or unmapped error. EV_ERROR_UNKNOWN = -999
    case unknown = -999

    /// Initialize from a raw C `ev_error_t` code, defaulting to `.unknown` for unmapped values.
    public static func from(code: Int32) -> NativeErrorCode {
        return NativeErrorCode(rawValue: code) ?? .unknown
    }

    /// Convert this native error code to an `EdgeVedaError`.
    ///
    /// Returns `nil` for `.ok` and `.streamEnded` since neither represents a failure.
    ///
    /// - Parameter context: Optional additional context string to include in the error message.
    /// - Returns: The corresponding `EdgeVedaError`, or `nil` if the code is not an error.
    public func toEdgeVedaError(context: String? = nil) -> EdgeVedaError? {
        let ctx = context ?? "Native engine error"

        switch self {
        case .ok, .streamEnded:
            return nil

        case .invalidParameter:
            return .invalidParameter(name: "native", value: ctx)

        case .outOfMemory:
            return .outOfMemory

        case .modelLoadFailed:
            return .loadFailed(reason: ctx)

        case .backendInitFailed:
            return .unsupportedBackend(.auto)

        case .inferenceFailed:
            return .generationFailed(reason: ctx)

        case .contextInvalid:
            return .ffiError(message: "Invalid context: \(ctx)")

        case .notImplemented:
            return .ffiError(message: "Not implemented: \(ctx)")

        case .memoryLimitExceeded:
            return .outOfMemory

        case .unsupportedBackend:
            return .unsupportedBackend(.auto)

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
