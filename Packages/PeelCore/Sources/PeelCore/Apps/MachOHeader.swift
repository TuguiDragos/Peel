import Darwin
import Foundation

enum MachOHeader {
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagic64: UInt32 = 0xCAFE_BABF
    private static let machMagic64Swapped: UInt32 = 0xCFFA_EDFE
    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let cpuTypeX86_64: UInt32 = 0x0100_0007
    private static let maximumFatArchitectures = 32
    /// `MH_EXECUTE` in `<mach-o/loader.h>`: a program, as opposed to a library or a bundle another program loads.
    private static let programFileType: UInt32 = 0x2

    /// Returns the architectures of the executable at `url`. Whatever is at that path gets opened, and a named
    /// pipe opened for reading would wait forever for a writer. `O_NONBLOCK` returns at once, and only a regular
    /// file is read.
    static func architectures(ofExecutableAt url: URL) -> Set<Architecture> {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return [] }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return [] }
        var bytes = [UInt8](repeating: 0, count: 4_096)
        let count = read(descriptor, &bytes, bytes.count)
        return count > 0 ? architectures(inHeader: Array(bytes[0..<count])) : []
    }

    /// Whether the file at `url` is a program of its own rather than code another program loads. A universal
    /// file is judged by its first slice, since every slice of one file is built as the same kind.
    static func isProgram(at url: URL) -> Bool {
        let descriptor = open(url.path(percentEncoded: false), O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        func bytes(at offset: off_t, count: Int) -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: count)
            let read = pread(descriptor, &buffer, count, offset)
            return read > 0 ? Array(buffer[0..<read]) : []
        }
        func isAProgram(_ header: [UInt8]) -> Bool {
            bigEndianUInt32(header, at: 0) == machMagic64Swapped
                && littleEndianUInt32(header, at: 12) == programFileType
        }
        let header = bytes(at: 0, count: 32)
        switch bigEndianUInt32(header, at: 0) {
        case machMagic64Swapped:
            return isAProgram(header)
        case fatMagic:
            guard let offset = bigEndianUInt32(header, at: 16) else { return false }
            return isAProgram(bytes(at: off_t(offset), count: 16))
        case fatMagic64:
            guard let high = bigEndianUInt32(header, at: 16), let low = bigEndianUInt32(header, at: 20) else {
                return false
            }
            return isAProgram(bytes(at: off_t(UInt64(high) << 32 | UInt64(low)), count: 16))
        default:
            return false
        }
    }

    static func architectures(inHeader bytes: [UInt8]) -> Set<Architecture> {
        guard let magic = bigEndianUInt32(bytes, at: 0) else { return [] }

        switch magic {
        case fatMagic, fatMagic64:
            guard let count = bigEndianUInt32(bytes, at: 4).map(Int.init), count <= maximumFatArchitectures else {
                return []
            }
            let entrySize = magic == fatMagic64 ? 32 : 20
            return Set((0..<count).compactMap { index in
                bigEndianUInt32(bytes, at: 8 + index * entrySize).flatMap(architecture(cpuType:))
            })
        case machMagic64Swapped:
            return Set([littleEndianUInt32(bytes, at: 4).flatMap(architecture(cpuType:))].compactMap { $0 })
        default:
            return []
        }
    }

    private static func architecture(cpuType: UInt32) -> Architecture? {
        switch cpuType {
        case cpuTypeARM64: .arm64
        case cpuTypeX86_64: .x86_64
        default: nil
        }
    }

    private static func bigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func littleEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
