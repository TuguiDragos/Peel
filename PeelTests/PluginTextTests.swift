import Foundation
@testable import Peel
@testable import PeelCore
import Testing

struct PluginTextTests {
    private func plugin(
        _ path: String, name: String, forAllUsers: Bool = false, category: Plugin.Category = .audioUnits
    ) -> Plugin {
        Plugin(
            url: URL(filePath: path, directoryHint: .isDirectory), name: name, bundleIdentifier: nil, version: nil,
            category: category, isInstalledForAllUsers: forAllUsers, size: 1, requiresPrivileges: forAllUsers,
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

    @Test func saysMovingAPlugInNothingLoadsChangesNothing() {
        var generator = plugin(
            "/Users/org.example/Library/QuickLook/Markdown.qlgenerator", name: "Markdown", category: .quickLook
        )
        generator.noLongerLoaded = .quickLookGenerator
        var flash = plugin(
            "/Library/Internet Plug-Ins/Flash Player.plugin", name: "Flash Player", forAllUsers: true,
            category: .internetPlugIns
        )
        flash.noLongerLoaded = .internetPlugIn
        flash.staysInTheTrash = true
        let echo = plugin("/Users/org.example/Library/Audio/Plug-Ins/Components/Echo.component", name: "Echo")

        #expect(generator.whenMoved.map { String(localized: $0) } == [
            String(localized: "macOS no longer loads Quick Look generators like this one, so moving it changes nothing."),
        ])
        #expect(flash.whenMoved.map { String(localized: $0) } == [
            String(localized: "macOS and today’s browsers no longer load plug-ins like this one, so moving it changes nothing."),
            String(localized: "History can’t put it back, since Peel’s helper puts back into that folder only what is root’s alone, but you can drag it back out in Finder."),
            String(localized: "Every account on this Mac has it, so moving it takes it from all of them."),
        ])
        #expect(echo.whenMoved.map { String(localized: $0) } == [String(localized: "Apps that use it may stop working.")])
    }
}
