import Foundation
@testable import Peel
@testable import PeelCore
import Testing

@MainActor
struct OrphanPartsTests {
    @Test func aRemovalOfAGroupIsNamedAsThePageNamesIt() throws {
        let item = OrphanItem(
            url: URL(filePath: "/Users/me/Library/Application Support/org.example.chat"),
            kind: .applicationSupport, size: 10, modificationDate: nil, requiresPrivileges: false
        )
        var group = OrphanGroup(identifier: "org.example.chat", items: [item])
        group.rememberedApp = RememberedApp(
            bundleIdentifier: "org.example.chat", name: "Chat", teamIdentifier: nil, lastSeen: .now,
            lastPath: "/Applications/Chat.app"
        )

        let part = try #require(OrphanLibrary.parts(of: [group], selecting: [item.url]).first)

        #expect(part.title == "Chat")
        #expect(part.source == "Chat")
    }
}
