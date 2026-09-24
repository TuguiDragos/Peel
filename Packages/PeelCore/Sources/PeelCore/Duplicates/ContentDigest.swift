import CryptoKit
import Foundation

/// A SHA-256 digest stored as its 32 bytes, so a digest read back from disk equals a freshly computed one.
/// `SHA256.Digest` itself cannot be created from bytes.
struct ContentDigest: Hashable, Sendable {
    static let byteCount = 32

    private let first: UInt64
    private let second: UInt64
    private let third: UInt64
    private let fourth: UInt64

    init(_ digest: SHA256.Digest) {
        self = digest.withUnsafeBytes { ContentDigest(raw: $0) }
    }

    init?(bytes: [UInt8]) {
        guard bytes.count == Self.byteCount else { return nil }
        self = bytes.withUnsafeBytes { ContentDigest(raw: $0) }
    }

    private init(raw: UnsafeRawBufferPointer) {
        first = raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self)
        second = raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
        third = raw.loadUnaligned(fromByteOffset: 16, as: UInt64.self)
        fourth = raw.loadUnaligned(fromByteOffset: 24, as: UInt64.self)
    }

    var bytes: [UInt8] {
        withUnsafeBytes(of: (first, second, third, fourth)) { Array($0) }
    }

    var hexadecimal: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
