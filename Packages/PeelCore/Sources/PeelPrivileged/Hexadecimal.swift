private let hexadecimalDigits = Array("0123456789abcdef".utf8)

extension Sequence<UInt8> {
    /// The bytes as lowercase hexadecimal, two digits each, as `String(format: "%02x")` writes them, which costs a
    /// formatter per byte.
    public var hexadecimal: String {
        var text: [UInt8] = []
        text.reserveCapacity(underestimatedCount * 2)
        for byte in self {
            text.append(hexadecimalDigits[Int(byte >> 4)])
            text.append(hexadecimalDigits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}
