import Foundation
import Testing

/// The wallet IDs that `BrowserWallets.swift` names in its comments, read from the source while a test runs. A test
/// binary that carried them as text would be taken for a program that steals wallets: XProtect, the malware scanner
/// built into macOS, moves such a binary to the Trash.
enum WalletIDs {
    struct Entry {
        let name: String
        let id: String
        let fingerprint: String
    }

    static let source = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/PeelPrivileged/BrowserWallets.swift")

    /// MetaMask's ID in the Chrome Web Store, and its add-on ID in Firefox.
    static var metaMask: String { id(of: "MetaMask", in: "walletExtensions") }
    static var metaMaskForFirefox: String { id(of: "MetaMask", in: "walletAddOns") }

    /// The entries of the list declared as `list`: each fingerprint, with the name and the ID in the comment above.
    static func entries(of list: String) throws -> [Entry] {
        let text = try String(contentsOf: source, encoding: .utf8)
        guard
            let start = text.range(of: "static let \(list): Set<String> = ["),
            let end = text.range(of: "\n    ]", range: start.upperBound..<text.endIndex)
        else { return [] }

        var entries: [Entry] = []
        var named: (name: String, id: String)?
        for line in text[start.upperBound..<end.lowerBound].split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("// "), let colon = line.range(of: ": ", options: .backwards) {
                named = (
                    String(line[line.index(line.startIndex, offsetBy: 3)..<colon.lowerBound]),
                    String(line[colon.upperBound...])
                )
            } else if line.hasPrefix("\""), let wallet = named {
                entries.append(
                    Entry(name: wallet.name, id: wallet.id, fingerprint: String(line.dropFirst().prefix(64)))
                )
                named = nil
            }
        }
        return entries
    }

    private static func id(of name: String, in list: String) -> String {
        guard let entry = (try? entries(of: list))?.first(where: { $0.name == name }) else {
            Issue.record("BrowserWallets.swift names no \(name) in \(list)")
            return ""
        }
        return entry.id
    }
}
