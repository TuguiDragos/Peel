import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct PluginTextTests {
    private func plugin(_ path: String, name: String, forAllUsers: Bool = false) -> Plugin {
        Plugin(
            url: URL(filePath: path, directoryHint: .isDirectory), name: name, bundleIdentifier: nil, version: nil,
            category: .audioUnits, isInstalledForAllUsers: forAllUsers, size: 1, requiresPrivileges: forAllUsers,
            refusal: nil
        )
    }

    @Test func findsAPlugInByTheNameFinderShows() {
        let product = plugin("/Library/Audio/Plug-Ins/Components/Vendor Product.component", name: "Product")

        #expect(product.matches("Vendor"))
        #expect(product.matches("Product"))
    }

    @Test func tellsTheCopyForAllUsersOfAPlugInInBothLibraries() {
        let mine = plugin("/Users/org.example/Library/Audio/Plug-Ins/Components/Echo.component", name: "Echo")
        let everyones = plugin("/Library/Audio/Plug-Ins/Components/Echo.component", name: "Echo", forAllUsers: true)
        let alone = plugin("/Library/Audio/Plug-Ins/Components/Reverb.component", name: "Reverb", forAllUsers: true)

        #expect(Plugin.sayingForAllUsers([mine, everyones, alone]) == [everyones.id])
    }

    @Test func saysAMoveTakesAPlugInInLibraryFromEveryAccount() {
        let mine = plugin("/Users/org.example/Library/Audio/Plug-Ins/Components/Echo.component", name: "Echo")
        let everyones = plugin("/Library/Audio/Plug-Ins/Components/Echo.component", name: "Echo", forAllUsers: true)
        let everyAccount = String(localized: "Every account on this Mac has it, so moving it takes it from all of them.")

        #expect(mine.whenMoved.map { String(localized: $0) }.last != everyAccount)
        #expect(everyones.whenMoved.map { String(localized: $0) }.last == everyAccount)
    }
}
