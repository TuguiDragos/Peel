import CryptoKit
import Darwin
import Foundation

enum FileDigest {
    static let sampleLength = 64 * 1024
    private static let chunkLength = 1024 * 1024
    private static let concurrentReads = 4

    static func isSampled(size: Int64) -> Bool {
        size > Int64(2 * sampleLength)
    }

    /// The bytes that reading these files in full will take, leaving out files whose full digest is remembered.
    static func bytesToRead(_ identities: [FileIdentity], known: KnownDigests?) -> Int64 {
        identities.filter { known?.full(of: $0) == nil }.reduce(0) { $0 + $1.size }
    }

    /// Digests `items`, `concurrentReads` at a time, leaving out any that cannot be read. Once the task is
    /// canceled, no new read starts.
    static func many<Item: Sendable>(
        _ items: [Item],
        digest: @escaping @Sendable (Item) -> ContentDigest?,
        onCompletion: (Int) -> Void = { _ in }
    ) async -> [(item: Item, digest: ContentDigest)] {
        await withTaskGroup(of: (item: Item, digest: ContentDigest)?.self) { group in
            var pending = items.makeIterator()
            var results: [(item: Item, digest: ContentDigest)] = []
            var completed = 0
            for _ in 0..<concurrentReads {
                guard let item = pending.next() else { break }
                group.addTask { digest(item).map { (item: item, digest: $0) } }
            }
            while let result = await group.next() {
                if let result {
                    results.append(result)
                }
                completed += 1
                onCompletion(completed)
                if !Task.isCancelled, let item = pending.next() {
                    group.addTask { digest(item).map { (item: item, digest: $0) } }
                }
            }
            return results
        }
    }

    /// SHA-256 of the first and last `sampleLength` bytes, or of the whole file when it isn't longer than both.
    static func sample(of url: URL, identity: FileIdentity, known: KnownDigests? = nil) -> ContentDigest? {
        if let digest = known?.sample(of: identity) { return digest }
        // Each buffer is only as large as the read it serves, not `chunkLength`: this pass runs for every
        // candidate and reads at most 128 KiB of each.
        let digest = isSampled(size: identity.size)
            ? read(url, bufferLength: sampleLength, identity: identity) { descriptor, buffer, hasher in
                readFully(descriptor, count: sampleLength, offset: 0, buffer: buffer, into: &hasher)
                    && readFully(
                        descriptor,
                        count: sampleLength,
                        offset: identity.size - Int64(sampleLength),
                        buffer: buffer,
                        into: &hasher
                    )
            }
            : whole(url, identity: identity)
        if let digest { known?.keep(sample: digest, of: identity) }
        return digest
    }

    static func full(
        of url: URL,
        identity: FileIdentity,
        known: KnownDigests? = nil,
        onRead: (Int) -> Void = { _ in }
    ) -> ContentDigest? {
        if let digest = known?.full(of: identity) { return digest }
        let digest = whole(url, identity: identity, onRead: onRead)
        if let digest { known?.keep(full: digest, of: identity) }
        return digest
    }

    private static func whole(_ url: URL, identity: FileIdentity, onRead: (Int) -> Void = { _ in }) -> ContentDigest? {
        read(
            url,
            bufferLength: Int(min(Int64(chunkLength), max(identity.size, 1))),
            identity: identity
        ) { descriptor, buffer, hasher in
            var offset: Int64 = 0
            while offset < identity.size {
                guard !Task.isCancelled else { return false }
                let count = Int(min(Int64(buffer.count), identity.size - offset))
                guard readFully(descriptor, count: count, offset: offset, buffer: buffer, into: &hasher) else {
                    return false
                }
                offset += Int64(count)
                onRead(count)
            }
            return true
        }
    }

    /// Hashes the file at `url` through `body`, without following a link and without filling the file cache.
    /// Returns nil when it cannot be read, or when it does not match `identity` both before and after the read.
    private static func read(
        _ url: URL,
        bufferLength: Int = chunkLength,
        identity: FileIdentity,
        body: (Int32, UnsafeMutableRawBufferPointer, inout SHA256) -> Bool
    ) -> ContentDigest? {
        // `O_NONBLOCK`: between the listing and this open, the path can become a pipe, and without the flag
        // opening a pipe can wait forever (`man 2 open`). The identity check below then refuses anything that is
        // not the expected file.
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_NOCACHE, 1)
        guard matches(descriptor, identity) else { return nil }

        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: max(bufferLength, 1), alignment: 1)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        guard body(descriptor, buffer, &hasher), matches(descriptor, identity) else { return nil }
        return ContentDigest(hasher.finalize())
    }

    private static func matches(_ descriptor: Int32, _ identity: FileIdentity) -> Bool {
        var info = stat()
        return fstat(descriptor, &info) == 0 && FileIdentity(info) == identity
    }

    private static func readFully(
        _ descriptor: Int32,
        count: Int,
        offset: Int64,
        buffer: UnsafeMutableRawBufferPointer,
        into hasher: inout SHA256
    ) -> Bool {
        var done = 0
        while done < count {
            let result = pread(descriptor, buffer.baseAddress, count - done, offset + Int64(done))
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { return false }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer.baseAddress, count: result))
            done += result
        }
        return true
    }
}
