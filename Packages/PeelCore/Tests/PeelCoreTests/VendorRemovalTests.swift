import Foundation
@testable import PeelCore
import Testing

struct VendorRemovalTests {
    private func app(in directory: borrowing TemporaryDirectory, path: String, name: String, identifier: String = "com.example.app") -> InstalledApp {
        InstalledApp(url: directory.url.appending(path: path, directoryHint: .isDirectory), bundleIdentifier: identifier, name: name)
    }

    @Test func findsAnUninstallerShippedWithTheApp() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Suite/Example.app/Contents/Resources/Uninstall Example.app")
        let example = app(in: directory, path: "Suite/Example.app", name: "Example")

        let uninstaller = try #require(VendorRemoval.uninstaller(for: example))
        #expect(uninstaller.lastPathComponent == "Uninstall Example.app")
    }

    @Test func findsAnUninstallerNextToTheApp() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Suite/Example.app")
        try directory.directory("Suite/Example Uninstaller.app")
        let example = app(in: directory, path: "Suite/Example.app", name: "Example")

        #expect(VendorRemoval.uninstaller(for: example)?.lastPathComponent == "Example Uninstaller.app")
    }

    @Test func ignoresUnrelatedAppsNextToIt() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Suite/Example.app")
        try directory.directory("Suite/Helper.app")
        let example = app(in: directory, path: "Suite/Example.app", name: "Example")

        #expect(VendorRemoval.uninstaller(for: example) == nil)
        #expect(!VendorRemoval.isUninstallerName("Helper.app", app: example))
        #expect(VendorRemoval.isUninstallerName("Uninstall.app", app: example))
    }

    /// Another product's uninstaller is never this app's, whether it sits at the top of an Applications folder
    /// or in a vendor's folder. A folder URL ends in a slash, and `isApplicationsFolder` still has to
    /// recognize it.
    @Test func anotherProductsUninstallerIsNotThisApps() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Applications/Example.app")
        try directory.directory("Applications/Uninstall Pulse Secure.app")
        try directory.directory("Applications/Other Product Uninstaller.app")
        try directory.directory("Suite/Example.app")
        try directory.directory("Suite/Uninstall Other Product.app")

        #expect(VendorRemoval.isApplicationsFolder(URL(filePath: "/Applications/Example.app").deletingLastPathComponent()))
        #expect(VendorRemoval.uninstaller(for: app(in: directory, path: "Applications/Example.app", name: "Example")) == nil)
        #expect(VendorRemoval.uninstaller(for: app(in: directory, path: "Suite/Example.app", name: "Example")) == nil, "a vendor's folder holds its other products too")
    }

    /// In Homebrew's casks, an uninstaller app sits inside the bundle, beside it, at the top of `/Applications`
    /// (Chrome Remote Desktop Host Uninstaller), or in a maker's folder in Utilities (Adobe Installers). The
    /// last two hold every maker's uninstallers, so there the name must be the app's own name with only
    /// "Uninstall" or "Uninstaller" added.
    @Test func findsAnUninstallerThatNamesTheAppWhereEveryMakerKeepsTheirs() throws {
        let directory = try TemporaryDirectory()
        let applications = directory.url.appending(path: "Applications", directoryHint: .isDirectory)
        try directory.directory("Applications/Chrome Remote Desktop Host.app")
        try directory.directory("Applications/Chrome Remote Desktop Host Uninstaller.app")
        try directory.directory("Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app")
        try directory.directory("Applications/Utilities/Adobe Installers/Uninstall Adobe Photoshop 2025.app")
        try directory.directory("Applications/Photos.app")
        try directory.directory("Applications/Uninstall Photoshop.app")

        let chrome = app(in: directory, path: "Applications/Chrome Remote Desktop Host.app", name: "Chrome Remote Desktop Host")
        let photoshop = app(in: directory, path: "Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app", name: "Adobe Photoshop 2025")
        let photos = app(in: directory, path: "Applications/Photos.app", name: "Photos")

        #expect(VendorRemoval.uninstaller(for: chrome, applicationsFolders: [applications])?.lastPathComponent == "Chrome Remote Desktop Host Uninstaller.app")
        #expect(VendorRemoval.uninstaller(for: photoshop, applicationsFolders: [applications])?.lastPathComponent == "Uninstall Adobe Photoshop 2025.app")
        #expect(VendorRemoval.uninstaller(for: photos, applicationsFolders: [applications]) == nil, "Photoshop's uninstaller names more than Photos")
    }

    @Test func listsSystemExtensionsInsideTheBundle() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("Example.app/Contents/Library/SystemExtensions/com.example.app.filter.systemextension")
        try directory.directory("Example.app/Contents/Library/SystemExtensions/notes.txt")
        let example = app(in: directory, path: "Example.app", name: "Example")

        #expect(VendorRemoval.systemExtensions(in: example) == ["com.example.app.filter.systemextension"])
    }

    @Test func showsOnlyFilesAPackagePutOutsideTheApp() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        try directory.file("Applications/Example.app/Contents/MacOS/Example")
        let tool = try directory.file("usr/local/bin/example")
        let shared = try directory.file("Library/Application Support/Shared/config.plist")
        let folder = try directory.directory("Library/Application Support/Example")

        let example = InstalledApp(url: bundle, bundleIdentifier: "com.example.app", name: "Example")
        let receipt = PackageReceipt(
            identifier: "com.example.app.pkg",
            version: "1.0",
            installDate: nil,
            volume: directory.url,
            items: [
                PackageReceipt.Item(url: bundle, size: 10, requiresPrivileges: false),
                PackageReceipt.Item(url: tool, size: 20, requiresPrivileges: true),
                PackageReceipt.Item(url: shared, size: 30, requiresPrivileges: false),
                PackageReceipt.Item(url: folder, size: 40, requiresPrivileges: false),
            ]
        )
        let other = PackageReceipt(
            identifier: "com.other.pkg",
            version: nil,
            installDate: nil,
            volume: directory.url,
            items: [PackageReceipt.Item(url: shared, size: 30, requiresPrivileges: false)]
        )

        let files = VendorRemoval.filesOutsideBundle(of: receipt, app: example, otherReceipts: [receipt, other])
        // The support folder counts: it is the most common thing a package leaves outside the app. Without it,
        // the list would suggest that everything the package installed lives inside the app.
        #expect(Set(files.map(\.url)) == [folder, tool])
    }

    /// The catalog writes an app's URL with a trailing slash, while a receipt's items are plain paths, so the two
    /// are compared as paths: the bundle is never among what the package put outside it, and neither is anything
    /// inside it, nor a file another receipt names in another spelling.
    @Test func comparesAReceiptWithTheAppAsPaths() throws {
        let directory = try TemporaryDirectory()
        let bundle = try directory.directory("Applications/Example.app")
        try directory.file("Applications/Example.app/Contents/MacOS/Example")
        let tool = try directory.file("usr/local/bin/example")
        let plain = { (url: URL) in URL(filePath: url.path(percentEncoded: false).removingSuffix("/")) }

        let example = InstalledApp(url: URL(filePath: bundle.path(percentEncoded: false), directoryHint: .isDirectory), bundleIdentifier: "com.example.app", name: "Example")
        let receipt = PackageReceipt(
            identifier: "com.example.app.pkg",
            version: "1.0",
            installDate: nil,
            volume: directory.url,
            items: [
                PackageReceipt.Item(url: plain(bundle), size: 10, requiresPrivileges: false),
                PackageReceipt.Item(url: plain(bundle).appending(path: "Contents/MacOS/Example"), size: 5, requiresPrivileges: false),
                PackageReceipt.Item(url: plain(tool), size: 20, requiresPrivileges: true),
            ]
        )

        let files = VendorRemoval.filesOutsideBundle(of: receipt, app: example, otherReceipts: [receipt])

        #expect(files.map(\.url) == [plain(tool)], "the app's own bundle was listed as outside it")
    }
}
