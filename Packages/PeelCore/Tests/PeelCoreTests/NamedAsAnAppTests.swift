import Foundation
@testable import PeelCore
import PeelLink
@testable import PeelPrivileged
import Testing
import UniformTypeIdentifiers

struct NamedAsAnAppTests {
    private func plist(_ values: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    @Test func anAppNamedInCapitalsOpensFromFinderALinkAndADrop() throws {
        let app = URL(filePath: "/Applications/Upper.APP", directoryHint: .isDirectory)
        #expect(OpenRequest.application(amongSelected: [app]) == app)
        #expect(OpenRequest.applicationURL(from: app) == app)
        #expect(OpenRequest.applicationURL(from: try #require(URL(string: "peel://open?path=/Applications/Mixed.App"))) != nil)
        let finder = URL(filePath: "/Applications/Peel.APP/Contents/PlugIns/PeelFinder.appex", directoryHint: .isDirectory)
        #expect(OpenRequest.hostApplication(ofExtensionAt: finder)?.lastPathComponent == "Peel.APP")
    }

    @Test func anAppNamedInCapitalsIsListedUnderItsName() async throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Apps")
        try directory.file("Apps/Upper.APP/Contents/Info.plist", contents: plist(["CFBundleIdentifier": "org.example.upper"]))

        let scan = await AppCatalog.scan(in: [folder])

        #expect(scan.apps.map(\.name) == ["Upper"])
    }

    @Test func theAppAroundAProgramOrAnExtensionIsFoundWhateverTheCase() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Upper.APP/Contents/Info.plist", contents: plist(["CFBundleIdentifier": "org.example.upper"]))
        let program = directory.url.appending(path: "Upper.APP/Contents/MacOS/upper").path(percentEncoded: false)

        #expect(BackgroundItemOwnership.bundle(holding: program)?.identifier == "org.example.upper")
        #expect(AppExtensions.app(ofExtensionAt: "/Applications/Upper.APP/Contents/PlugIns/Part.appex")?
            .lastPathComponent == "Upper.APP")
    }

    @Test func aLoginItemNamedInCapitalsIsOneOfTheAppsLabels() throws {
        let directory = try TemporaryDirectory()
        let app = try directory.directory("Tide.app")
        try directory.file(
            "Tide.app/Contents/Library/LoginItems/Helper.APP/Contents/Info.plist",
            contents: plist(["CFBundleIdentifier": "org.example.tide.helper"])
        )

        #expect(StartsAtLogin.labels(declaredBy: app) == ["org.example.tide.helper"])
    }

    @Test func anUninstallerNamedInCapitalsIsOne() {
        let example = InstalledApp(
            url: URL(filePath: "/Applications/Example.app", directoryHint: .isDirectory),
            bundleIdentifier: "org.example.app", name: "Example"
        )

        #expect(VendorRemoval.isUninstallerName("Uninstall Example.APP", app: example))
    }

    @Test func everyPartOfPeelReadsAnAppsNameAsMacOSDoes() throws {
        let directory = try TemporaryDirectory()
        let names = ["Tool.app", "Upper.APP", "Mixed.App", ".app", "..app", "Tool.apps", "Tool.app.zip", "Tool.app ", "Tool"]
        for name in names {
            try directory.file("\(name)/Contents/Info.plist", contents: plist([:]))
            let folder = directory.url.appending(path: name, directoryHint: .isDirectory)
            let type = try folder.resourceValues(forKeys: [.contentTypeKey]).contentType
            let isAnApp = type?.conforms(to: .applicationBundle) == true

            #expect(PathComponents.isNamedAsAnApp(name) == isAnApp, "\(name)")
            #expect(folder.isNamedAsAnApp == isAnApp, "\(name)")
            #expect((OpenRequest.applicationURL(from: folder) != nil) == isAnApp, "\(name), as the link reads it")
        }
    }

    @Test func noOtherPlaceReadsAnAppsNameItself() throws {
        let root = LineLengthTests.repository.path(percentEncoded: false)
        let product = ["Peel/", "PeelCLI/", "PeelFinder/", "PeelHelper/", "Packages/PeelCore/Sources/"]
        let rule = try NSRegularExpression(
            pattern: #"[!=]=\s*"app"|caseInsensitiveCompare\("app"\)|hasSuffix\("\.app/?"\)|"\.app/"|\(of: "\.app"#
        )
        let allowed = [
            "Packages/PeelCore/Sources/PeelPrivileged/PathComponents.swift": 1,
            "Packages/PeelCore/Sources/PeelLink/OpenRequest.swift": 1,
        ]
        var found: [String] = []
        for file in try LineLengthTests.swiftFiles() {
            let relative = String(file.path(percentEncoded: false).dropFirst(root.count))
            guard product.contains(where: relative.hasPrefix) else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            let count = rule.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if count != allowed[relative, default: 0] { found.append("\(relative): \(count)") }
        }
        #expect(found.isEmpty, "An app's name is read by PathComponents.isNamedAsAnApp: \(found)")
    }

    @Test func theHelperTakesPeelAndAnAppWhateverTheCaseOfTheirName() {
        #expect(PrivilegedPathPolicy.peelTool(besideHelperAt: "/Applications/Peel.APP/Contents/MacOS/PeelHelper")
            == "/Applications/Peel.APP/Contents/Helpers/peel")
        #expect(PrivilegedPathPolicy.peelTool(besideHelperAt: "/Applications/.app/Contents/MacOS/PeelHelper") == nil)
    }
}
