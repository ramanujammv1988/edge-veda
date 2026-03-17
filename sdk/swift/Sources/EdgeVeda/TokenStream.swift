import Foundation
import CEdgeVeda

/// AsyncSequence that yields tokens from streaming generation.
@available(iOS 15.0, macOS 12.0, *)
public struct TokenStream: AsyncSequence {
    public typealias Element = String

    let streamHandle: OpaquePointer

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(streamHandle: streamHandle)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let streamHandle: OpaquePointer
        private var finished = false

        init(streamHandle: OpaquePointer) {
            self.streamHandle = streamHandle
        }

        public mutating func next() async throws -> String? {
            if finished { return nil }

            return try await withCheckedThrowingContinuation { continuation in
                var error = EV_SUCCESS
                let tokenPtr = ev_stream_next(streamHandle, &error)

                if let tokenPtr = tokenPtr {
                    let token = String(cString: tokenPtr)
                    ev_free_string(tokenPtr)
                    continuation.resume(returning: token)
                } else if error == EV_ERROR_STREAM_ENDED || error == EV_SUCCESS {
                    finished = true
                    continuation.resume(returning: nil)
                } else {
                    finished = true
                    continuation.resume(throwing: EdgeVedaError.from(code: error))
                }
            }
        }
    }
}
