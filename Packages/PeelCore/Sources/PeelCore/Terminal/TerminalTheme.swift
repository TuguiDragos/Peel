public struct TerminalTheme: Sendable, Hashable, Identifiable {
    public let name: String
    public let background: UInt32
    public let text: UInt32
    public let cursor: UInt32
    public let selection: UInt32
    public let ansi: [UInt32]

    public var id: String { name }

    public var profileName: String { "Peel \(name)" }
}
