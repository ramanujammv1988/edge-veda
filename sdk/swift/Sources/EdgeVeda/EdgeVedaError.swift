import Foundation
import CEdgeVeda

/// Errors thrown by the Edge Veda SDK.
public enum EdgeVedaError: Error, LocalizedError {
    case invalidParameter(String)
    case outOfMemory(String)
    case modelLoadFailed(String)
    case backendInitFailed(String)
    case inferenceFailed(String)
    case contextInvalid(String)
    case streamEnded
    case notImplemented(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        case .outOfMemory(let msg): return "Out of memory: \(msg)"
        case .modelLoadFailed(let msg): return "Model load failed: \(msg)"
        case .backendInitFailed(let msg): return "Backend init failed: \(msg)"
        case .inferenceFailed(let msg): return "Inference failed: \(msg)"
        case .contextInvalid(let msg): return "Invalid context: \(msg)"
        case .streamEnded: return "Stream ended"
        case .notImplemented(let msg): return "Not implemented: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }

    static func from(code: ev_error_t) -> EdgeVedaError {
        let msg = String(cString: ev_error_string(code))
        switch code {
        case EV_ERROR_INVALID_PARAM: return .invalidParameter(msg)
        case EV_ERROR_OUT_OF_MEMORY, EV_ERROR_MEMORY_LIMIT_EXCEEDED: return .outOfMemory(msg)
        case EV_ERROR_MODEL_LOAD_FAILED: return .modelLoadFailed(msg)
        case EV_ERROR_BACKEND_INIT_FAILED: return .backendInitFailed(msg)
        case EV_ERROR_INFERENCE_FAILED: return .inferenceFailed(msg)
        case EV_ERROR_CONTEXT_INVALID: return .contextInvalid(msg)
        case EV_ERROR_STREAM_ENDED: return .streamEnded
        case EV_ERROR_NOT_IMPLEMENTED: return .notImplemented(msg)
        default: return .unknown(msg)
        }
    }
}
