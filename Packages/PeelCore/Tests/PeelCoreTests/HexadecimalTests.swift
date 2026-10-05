import CryptoKit
import Foundation
import PeelPrivileged
import Testing

struct HexadecimalTests {
    @Test func writesEachByteAsFormatDoes() {
        let every = (0...255).map(UInt8.init)

        #expect([0x00, 0x0F, 0xA5, 0xFF].hexadecimal == "000fa5ff")
        #expect(every.hexadecimal == every.map { String(format: "%02x", $0) }.joined())
        #expect(SHA256.hash(data: Data("Peel".utf8)).hexadecimal.count == 64)
        #expect([UInt8]().hexadecimal.isEmpty)
    }
}
