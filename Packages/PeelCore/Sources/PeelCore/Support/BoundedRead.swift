import Darwin
import Foundation

/// Reads a file only when it is small enough for the kind of file it should be. Most files Peel reads (an
/// `Info.plist`, a launchd job, an installer receipt) were written by other apps, so their size cannot be
/// trusted, and `Data(contentsOf:)` would load a file of any size into memory.
enum BoundedRead {
    /// 8 MB: generous for a property list, and too little memory to matter.
    static let maximumBytes = 8 * 1_024 * 1_024

    /// Reads from a descriptor as `read(2)` does. A parameter so a test can make a read fail partway.
    typealias Read = (_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int

    /// Returns the bytes of the regular file at `url`, or nil when it is anything else or larger than `maximum`.
    /// The file is opened once and checked through its descriptor: checking the path first and reading it
    /// after would let the file be swapped for a pipe in between. A symbolic link is followed, since users
    /// link launch agents and settings in from a repository.
    static func data(at url: URL, maximum: Int = maximumBytes, read: Read = { Darwin.read($0, $1, $2) }) -> Data? {
        guard let descriptor = openRegularFile(at: url, maximum: maximum) else { return nil }
        defer { close(descriptor) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while data.count <= maximum {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count == 0 {
                break
            } else if errno != EINTR {
                // What was read before the failure is part of the file, which is not the file.
                return nil
            }
        }
        return data.count <= maximum ? data : nil
    }

    /// The first `count` bytes of the regular file at `url`, or the whole file when it is shorter, whatever its size.
    static func prefix(of url: URL, count: Int) -> Data? {
        guard let descriptor = openRegularFile(at: url, maximum: .max) else { return nil }
        defer { close(descriptor) }

        var buffer = [UInt8](repeating: 0, count: count)
        var filled = 0
        while filled < count {
            let read = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress! + filled, count - filled)
            }
            if read > 0 {
                filled += read
            } else if read == 0 {
                break
            } else if errno != EINTR {
                return nil
            }
        }
        return Data(buffer[0..<filled])
    }

    /// Whether `url` opens as a regular file of at most `maximum` bytes, which is what `data(at:maximum:)` asks
    /// before it reads.
    static func opens(_ url: URL, maximum: Int = maximumBytes) -> Bool {
        guard let descriptor = openRegularFile(at: url, maximum: maximum) else { return false }
        close(descriptor)
        return true
    }

    /// A descriptor for the regular file at `url` when it is at most `maximum` bytes, which the caller closes.
    private static func openRegularFile(at url: URL, maximum: Int) -> Int32? {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= maximum else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    static func propertyList(at url: URL, maximum: Int = maximumBytes) -> [String: Any]? {
        data(at: url, maximum: maximum).flatMap(propertyList(in:))
    }

    static func propertyList(in data: Data) -> [String: Any]? {
        try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }
}
