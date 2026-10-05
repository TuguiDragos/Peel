import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct PluginsTests {
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...30 {
            try directory.directory("home/Library/Audio/Plug-Ins/VST3/Plug-in \(index).vst3/Contents")
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let unanswered = Unanswered()

        let stop = try await unanswered.stop {
            _ = await Plugins.scan(environment: environment, exclusions: .none, measure: unanswered.measure)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    @Test func findsPluginBundlesInUserAndSystemLibraries() async throws {
        let directory = try TemporaryDirectory()
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleName": "Reverb", "CFBundleIdentifier": "com.example.reverb", "CFBundleShortVersionString": "2.1"],
            format: .xml,
            options: 0
        )
        try info.write(to: directory.file("home/Library/Audio/Plug-Ins/Components/Reverb.component/Contents/Info.plist"))
        try directory.directory("root/Library/Audio/Plug-Ins/HAL/Parrot.driver")
        try directory.directory("home/Library/Services/Ask.workflow")
        try directory.directory("home/Library/Spotlight/ExtensionsCache")
        try directory.file("home/Library/QuickLook/readme.txt")

        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let plugins = await Plugins.scan(environment: environment)

        #expect(plugins.map(\.name) == ["Ask", "Parrot", "Reverb"])
        let reverb = try #require(plugins.last)
        #expect(reverb.category == .audioUnits)
        #expect(reverb.bundleIdentifier == "com.example.reverb")
        #expect(reverb.version == "2.1")
        #expect(!reverb.isInstalledForAllUsers)
        #expect(plugins.first { $0.name == "Parrot" }?.isInstalledForAllUsers == true)
    }

    /// Avid, MOTU and Apple each document a folder their plug-ins are installed in: AAX, MAS, Core Image's image
    /// units, dictionaries, Automator's actions and Contacts' action plug-ins.
    @Test func findsThePlugInsOfEveryFolderTheirMakersDocument() async throws {
        let directory = try TemporaryDirectory()
        let bundles = [
            "root/Library/Application Support/Avid/Audio/Plug-Ins/Echo.aaxplugin",
            "root/Library/Audio/Plug-Ins/MAS/Delay.bundle",
            "home/Library/Graphics/Image Units/Grain.plugin",
            "home/Library/Dictionaries/Glossary.dictionary",
            "root/Library/Automator/Resize.action",
            "home/Library/Address Book Plug-Ins/Dial.bundle",
        ]
        for bundle in bundles { try directory.directory("\(bundle)/Contents") }

        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let plugins = await Plugins.scan(environment: environment)
        let found = Dictionary(uniqueKeysWithValues: plugins.map { ($0.name, $0.category) })

        #expect(found == [
            "Echo": .aax, "Delay": .mas, "Grain": .imageUnits, "Glossary": .dictionaries, "Resize": .automatorActions,
            "Dial": .contactsPlugIns,
        ])
    }

    @Test func offersAMailBundleInTheUsersLibrary() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Mail/Bundles/Example.mailbundle/Contents")
        try directory.directory("home/Library/Audio/Plug-Ins/VST3/Synth.vst3/Contents")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let plugins = await Plugins.scan(environment: environment)

        #expect(try #require(plugins.first { $0.category == .mailBundles }).refusal == nil)
        #expect(try #require(plugins.first { $0.category == .vst3 }).refusal == nil)
    }

    /// Vendors keep their plug-ins in a folder of their own, and that folder's name can seem to have an
    /// extension: `Waves 14.0` reads as extension `0`.
    @Test func findsPluginsInsideAVendorsOwnFolder() async throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Audio/Plug-Ins/VST3/Waves 14.0/Reverb.vst3/Contents")
        try directory.directory("home/Library/Audio/Plug-Ins/VST3/Company/Delay.vst3/Contents")
        try directory.directory("home/Library/Audio/Plug-Ins/VST3/Loose.vst3/Contents")
        try directory.file("home/Library/Audio/Plug-Ins/VST3/Company/readme.txt")
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let plugins = await Plugins.scan(environment: environment)

        #expect(plugins.map(\.name) == ["Delay", "Loose", "Reverb"])
        #expect(!plugins.contains { $0.name.hasPrefix("Waves") }, "the vendor's folder was taken for a plug-in")
    }

    @Test func aPluginThatDidNotAnswerInTimeIsNotReadAsEmpty() async throws {
        let directory = try TemporaryDirectory()
        try directory.file("home/Library/Audio/Plug-Ins/VST3/Slow.vst3/Contents/Resources/samples.bin", bytes: 400_000)
        try directory.file("home/Library/Audio/Plug-Ins/VST3/Quick.vst3/Contents/Resources/samples.bin", bytes: 400_000)
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )

        let plugins = await Plugins.scan(environment: environment, exclusions: .none) { url in
            url.lastPathComponent == "Slow.vst3" ? nil : await FileSize.reclaimableSize(of: url, within: FileSize.budget)
        }

        #expect(plugins.map(\.name) == ["Quick", "Slow"])
        #expect(try #require(plugins.first?.size) >= 400_000)
        #expect(plugins.last?.size == nil)
    }

    /// Every folder the page reads plug-ins from in `/Library` is one the helper serves: a folder only the page
    /// knew would list plug-ins the helper then refuses to move out of it. The two lists are kept apart because
    /// the helper cannot see PeelCore, so this is where they meet.
    @Test func theHelperServesEveryFolderPlugInsAreReadFrom() {
        let served = Set(PrivilegedPathPolicy.systemLocations)
        for (folder, _) in Plugins.folders {
            #expect(served.contains("/Library/" + folder), "/Library/\(folder) is read and not served")
        }
    }

    /// Apple installs components into `/Library` too, and removing one breaks macOS. Any bundle can call itself
    /// `com.apple.…`, so Apple's code is known by its signature, not by its name.
    @Test func tellsApplesOwnCodeFromAnAppsBySignature() throws {
        // Finder is Apple's and is on every Mac. Its path starts with `/System`, which is Apple's by where it sits,
        // so the signature is asked about through a link to it from a folder that is nobody's.
        let finder = URL(filePath: "/System/Library/CoreServices/Finder.app", directoryHint: .isDirectory)
        try #require(FileManager.default.fileExists(atPath: finder.path(percentEncoded: false)))
        let directory = try TemporaryDirectory()
        let link = directory.url.appending(path: "Finder.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: finder)
        #expect(!AppleCode.isInASystemFolder(link.path(percentEncoded: false)))
        #expect(AppleCode.isApples(link), "Apple's own signature wasn't recognized")

        let impostor = try directory.directory("Impostor.driver/Contents")
        try PropertyListSerialization
            .data(fromPropertyList: ["CFBundleIdentifier": "com.apple.audio.Impostor"], format: .xml, options: 0)
            .write(to: impostor.appending(path: "Info.plist"))
        #expect(!AppleCode.isApples(impostor.deletingLastPathComponent()), "an Apple name was taken for an Apple signature")
    }

    /// macOS installs its own plug-ins into the same folders apps use, such as `ParrotAudioPlugin.driver` in
    /// `/Library/Audio/Plug-Ins/HAL`. The test checks names, since asking the scan's own signature question
    /// again would test nothing.
    @Test func leavesApplesOwnComponentsOutOfTheList() async {
        let listed = await Plugins.scan().map(\.name)
        #expect(!listed.contains("ParrotAudioPlugin"))
        #expect(!listed.contains { $0.hasPrefix("AU") && $0 != "AULab" }, "Apple's own audio units were listed: \(listed)")
    }
}
