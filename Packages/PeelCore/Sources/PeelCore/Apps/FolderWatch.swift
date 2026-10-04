import CoreServices
public import Foundation

/// Reports changes in folders. Apps are installed and removed while Peel is open, so a list read only at
/// launch would soon be out of date.
public enum FolderWatch {
    /// A burst of changes is one change: macOS gathers them for this long before it says anything.
    private static let latency: CFTimeInterval = 1
    /// How often, in seconds, the folders count as changed when macOS cannot watch them.
    private static let lookingAgain: TimeInterval = 60

    /// Yields a value whenever something changes anywhere under `folders`, subfolders included, since the
    /// catalog finds apps a few folders down (`/Applications/Setapp/Foo.app`). A folder that does not exist yet
    /// (`~/Applications` on a new Mac) is watched from the moment it is created. The watch ends when the stream
    /// is dropped.
    public static func changes(in folders: [URL]) -> AsyncStream<Void> {
        changes(in: folders, starting: FSEventStreamStart, orEvery: lookingAgain)
    }

    /// `start` starts the event stream. Apple says a stream ought always to start, and to fall back to looking at
    /// the folders again when it does not (`FSEventStreamStart`), so then a change is reported every `interval`.
    static func changes(
        in folders: [URL],
        starting start: @escaping @Sendable (FSEventStreamRef) -> Bool,
        orEvery interval: TimeInterval
    ) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let listener = Listener(continuation)
            var context = Self.context(owning: listener)
            let paths = folders.map { $0.path(percentEncoded: false) } as CFArray
            let created = withExtendedLifetime(listener) {
                FSEventStreamCreate(
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
                )
            }
            guard let stream = created else {
                lookAgain(every: interval, continuation)
                return
            }
            let watch = Watch(stream: stream)
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            guard start(stream) else {
                watch.end()
                lookAgain(every: interval, continuation)
                return
            }
            watch.isStarted = true
            continuation.onTermination = { _ in watch.end() }
        }
    }

    /// A context through which the stream keeps `info` until the stream is deallocated. Stopping, invalidating and
    /// releasing a stream wait for no callback, while the stream itself lives until a callback already running
    /// returns, so what the callback uses must go with the stream and not before.
    static func context(owning info: AnyObject) -> FSEventStreamContext {
        FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(info).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<AnyObject>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<AnyObject>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
    }

    private static func lookAgain(every interval: TimeInterval, _ continuation: AsyncStream<Void>.Continuation) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { continuation.yield() }
        timer.resume()
        continuation.onTermination = { _ in timer.cancel() }
    }

    private final class Listener: Sendable {
        let continuation: AsyncStream<Void>.Continuation

        init(_ continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }
    }

    /// Owns the event stream. `end()` stops and releases it, and must run exactly once. Only a stream that started
    /// is stopped, as `FSEventStreamStop` requires.
    private final class Watch: @unchecked Sendable {
        private let stream: FSEventStreamRef
        var isStarted = false

        init(stream: FSEventStreamRef) {
            self.stream = stream
        }

        func end() {
            if isStarted {
                FSEventStreamStop(stream)
            }
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
