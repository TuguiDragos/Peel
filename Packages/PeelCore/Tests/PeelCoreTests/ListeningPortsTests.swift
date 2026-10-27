import Darwin
@testable import PeelCore
import Testing

struct ListeningPortsTests {
    /// A socket listening on a port the kernel chooses, on the loopback only.
    static func listeningSocket() throws -> (socket: Int32, port: Int) {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        try #require(socket >= 0)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, size) }
        }
        try #require(bound == 0 && listen(socket, 1) == 0)
        var named = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &named) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &length) }
        }
        return (socket, Int(UInt16(bigEndian: named.sin_port)))
    }

    @Test func readsThePortsThisAccountListensOn() throws {
        let (socket, port) = try Self.listeningSocket()
        #expect(ListeningPorts.listening(by: getpid()).contains(port))
        #expect(ListeningPorts.ofThisAccount().contains(port))
        close(socket)
        #expect(!ListeningPorts.listening(by: getpid()).contains(port))
    }
}
