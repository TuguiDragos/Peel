import CoreServices
public import Foundation

/// Reports changes in folders. Apps are installed and removed while Peel is open, so a list read only at
/// launch would soon be out of date.
public enum FolderWatch {
    /// A burst of changes is one change: macOS gathers them for this long before it says anything.
    private static let latency: CFTimeInterval = 1

    /// Yields a value whenever something changes anywhere under `folders`, subfolders included, since the
    /// catalog finds apps a few folders down (`/Applications/Setapp/Foo.app`). A folder that does not exist yet
    /// (`~/Applications` on a new Mac) is watched from the moment it is created. The watch ends when the stream
    /// is dropped.
    public static func changes(in folders: [URL]) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let listener = Unmanaged.passRetained(Listener(continuation))
            var context = FSEventStreamContext(version: 0, info: listener.toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let paths = folders.map { $0.path(percentEncoded: false) } as CFArray
            guard let stream = FSEventStreamCreate(
                nil,
                { _, info, _, _, _, _ in
                    guard let info else { return }
                    Unmanaged<Listener>.fromOpaque(info).takeUnretainedValue().continuation.yield()
                },
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot)
            ) else {
                listener.release()
                continuation.finish()
                return
            }
            let watch = Watch(stream: stream, listener: listener)
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            guard FSEventStreamStart(stream) else {
                watch.end()
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in watch.end() }
        }
    }

    private final class Listener: Sendable {
        let continuation: AsyncStream<Void>.Continuation

        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }

    /// Owns the event stream and the listener its callback uses. `end()` stops and releases both, and must run
    /// exactly once.
    private final class Watch: @unchecked Sendable {
        private let stream: FSEventStreamRef
        private let listener: Unmanaged<Listener>

        init(stream: FSEventStreamRef, listener: Unmanaged<Listener>) {
            self.stream = stream
            self.listener = listener
        }

        func end() {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            listener.release()
        }
    }
}
