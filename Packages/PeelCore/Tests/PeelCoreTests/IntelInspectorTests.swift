import Foundation
@testable import PeelCore
import Testing

struct IntelInspectorTests {
    /// A fat header listing the given CPU types, which is all the reader looks at.
    private func fatHeader(_ cpuTypes: [UInt32]) -> Data {
        var bytes: [UInt8] = []
        func append(_ value: UInt32) {
            bytes += [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
        }
        append(0xCAFE_BABE)
        append(UInt32(cpuTypes.count))
        for cpuType in cpuTypes {
            append(cpuType)
            append(0)
            append(0)
            append(0)
            append(0)
        }
        return Data(bytes)
    }

    /// A 64 bit Intel Mach-O header of the given file type: 2 is a program, 8 a bundle loaded into another one.
    private func intelHeader(fileType: UInt8) -> Data {
        Data([0xCF, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00, 0x00, fileType, 0x00, 0x00, 0x00])
    }

    private let intel: UInt32 = 0x0100_0007
    private let appleSilicon: UInt32 = 0x0100_000C

    /// The drivers, the background items, and the tools are scanned after the apps, and those later steps must
    /// stop as well.
    @Test func aStoppedScanStops() async throws {
        let directory = try TemporaryDirectory()
        var apps: [InstalledApp] = []
        for index in 1...30 {
            let url = try bundle(directory, "Apps/Intel \(index).app", cpuTypes: [intel])
            apps.append(InstalledApp(url: url, bundleIdentifier: "com.example.intel\(index)", name: "Intel \(index)", architectures: [.x86_64]))
        }
        let folder = try #require(IntelInspector.driverFolders.first)
        for index in 1...3 {
            _ = try bundle(directory, "home/Library/\(folder)/Driver \(index).driver", cpuTypes: [intel])
        }
        let environment = SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
        let unanswered = Unanswered()
        let installed = apps

        let stop = try await unanswered.stop {
            _ = await IntelInspector.scan(installedApps: installed, plugins: [], backgroundItems: [], exclusions: .none, environment: environment, measure: unanswered.measure)
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    private func bundle(_ directory: borrowing TemporaryDirectory, _ path: String, cpuTypes: [UInt32]) throws -> URL {
        let name = (path as NSString).lastPathComponent
        let executableName = (name as NSString).deletingPathExtension
        let executable = try directory.file("\(path)/Contents/MacOS/\(executableName)", contents: fatHeader(cpuTypes))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        try directory.file("\(path)/Contents/Info.plist", contents: Data("<plist></plist>".utf8))
        return directory.url.appending(path: path, directoryHint: .isDirectory)
    }

    @Test func tellsIntelOnlyBundlesFromUniversalOnes() throws {
        let directory = try TemporaryDirectory()
        let intelApp = try bundle(directory, "Intel.app", cpuTypes: [intel])
        let universalApp = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        let appleApp = try bundle(directory, "Apple.app", cpuTypes: [appleSilicon])

        #expect(IntelInspector.isIntelOnly(bundle: intelApp))
        #expect(!IntelInspector.isIntelOnly(bundle: universalApp))
        #expect(!IntelInspector.isIntelOnly(bundle: appleApp))
    }

    /// Apple's macOS 27 note names the folders its own Intel list may miss: "~/Library/Audio/Plug-Ins/*,
    /// ~/Library/Printers/, ~/Library/ColorPickers/". Each is searched whole, in the user's Library as well as in
    /// `/Library`, so a per-user driver or an ARA plug-in is reported too.
    @Test func looksWhereApplesOwnNoteSaysIntelPlugInsHide() async throws {
        let directory = try TemporaryDirectory()
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)
        let root = directory.url.appending(path: "root", directoryHint: .isDirectory)
        _ = try bundle(directory, "home/Library/Audio/Plug-Ins/ARA/Melody.bundle", cpuTypes: [intel])
        _ = try bundle(directory, "home/Library/Printers/Vendor.plugin", cpuTypes: [intel])
        _ = try bundle(directory, "root/Library/ColorPickers/Wheel.bundle", cpuTypes: [intel, appleSilicon])

        let scan = await IntelInspector.scan(
            installedApps: [],
            plugins: [],
            backgroundItems: [],
            exclusions: .none,
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: root),
            measure: { _ in 1 }
        )

        #expect(Set(scan.findings.map(\.name)) == ["Melody.bundle", "Vendor.plugin"])
        #expect(scan.findings.allSatisfy { $0.kind == .driver })
    }

    @Test func findsAnIntelTWAINDataSource() async throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "root/Library/Image Capture/TWAIN Data Sources/Scanner.ds", cpuTypes: [intel])

        let scan = await IntelInspector.scan(
            installedApps: [],
            plugins: [],
            backgroundItems: [],
            exclusions: .none,
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            measure: { _ in 1 }
        )

        #expect(scan.findings.map(\.name) == ["Scanner.ds"])
        #expect(scan.findings.allSatisfy { $0.kind == .driver })
    }

    @Test func findsTheIntelProgramsAPrinterDriverKeeps() async throws {
        let directory = try TemporaryDirectory()
        let vendor = "root/Library/Printers/Vendor"
        let filter = try directory.file("\(vendor)/Filter/rastertovendor", contents: intelHeader(fileType: 2))
        try directory.setPermissions(0o755, of: filter)
        let tool = try directory.file("\(vendor)/Tools/lowinktool", contents: fatHeader([intel, appleSilicon]))
        try directory.setPermissions(0o755, of: tool)
        let library = try directory.file("\(vendor)/Filter/libvendor.dylib", contents: intelHeader(fileType: 6))
        try directory.setPermissions(0o755, of: library)
        _ = try directory.file("\(vendor)/Filter/notrunnable", contents: intelHeader(fileType: 2))
        // A `.driver` is no package to macOS, so the walk goes inside it.
        let inside = try directory.file("\(vendor)/Port.driver/Contents/MacOS/Port", contents: intelHeader(fileType: 2))
        try directory.setPermissions(0o755, of: inside)
        _ = try bundle(directory, "root/Library/Audio/Plug-Ins/HAL/Device.driver", cpuTypes: [intel])

        let scan = await IntelInspector.scan(
            installedApps: [],
            plugins: [],
            backgroundItems: [],
            exclusions: .none,
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            measure: { _ in 1 }
        )

        #expect(Set(scan.findings.map(\.name)) == ["rastertovendor", "Port.driver", "Device.driver"])
        #expect(scan.findings.allSatisfy { $0.kind == .driver })
    }

    @Test func findsIntelHelpersInsideAUniversalApp() throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        _ = try bundle(directory, "Universal.app/Contents/Library/LoginItems/Launcher.app", cpuTypes: [intel])
        _ = try bundle(directory, "Universal.app/Contents/XPCServices/Service.xpc", cpuTypes: [intel, appleSilicon])
        _ = try bundle(directory, "Universal.app/Contents/PlugIns/Old.appex", cpuTypes: [intel])

        let plainHelper = try directory.file(
            "Universal.app/Contents/Helpers/updater", contents: intelHeader(fileType: 2)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plainHelper.path(percentEncoded: false))

        let found = IntelInspector.intelOnlyBundles(inside: directory.url.appending(path: "Universal.app", directoryHint: .isDirectory))
        #expect(Set(found.map(\.lastPathComponent)) == ["Launcher.app", "Old.appex", "updater"])
    }

    /// Apple's place for a helper tool is `Contents/MacOS` beside the main executable, and a Quick Look generator,
    /// a Spotlight importer or a system extension the app carries runs in a process of its own too.
    @Test func findsIntelToolsBesideTheMainExecutableAndInTheAppsLibrary() throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        let tool = try directory.file("Universal.app/Contents/MacOS/ffmpeg", contents: intelHeader(fileType: 2))
        try directory.setPermissions(0o755, of: tool)
        // A library the tool loads runs in the tool's process, not one of its own.
        let library = try directory.file("Universal.app/Contents/MacOS/7z.so", contents: intelHeader(fileType: 8))
        try directory.setPermissions(0o755, of: library)
        let appLibrary = "Universal.app/Contents/Library"
        _ = try bundle(directory, "\(appLibrary)/QuickLook/Preview.qlgenerator", cpuTypes: [intel])
        _ = try bundle(directory, "\(appLibrary)/Spotlight/Importer.mdimporter", cpuTypes: [intel])
        _ = try bundle(directory, "\(appLibrary)/SystemExtensions/Filter.systemextension", cpuTypes: [intel])

        let app = directory.url.appending(path: "Universal.app", directoryHint: .isDirectory)
        let found = IntelInspector.intelOnlyBundles(inside: app)

        #expect(Set(found.map(\.lastPathComponent)) == [
            "ffmpeg", "Preview.qlgenerator", "Importer.mdimporter", "Filter.systemextension",
        ])
    }

    /// A Homebrew installed for Intel keeps every command in `/usr/local/bin` as a link into its `Cellar`. The
    /// program the link leads to is what needs Rosetta, listed under the command's name.
    @Test func findsTheIntelProgramACommandLinkLeadsTo() throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("Cellar/tool/1.0/bin/tool", contents: fatHeader([intel]))
        try directory.setPermissions(0o755, of: program)
        let bin = try directory.directory("bin")
        try FileManager.default.createSymbolicLink(
            atPath: bin.appending(path: "tool").path(percentEncoded: false),
            withDestinationPath: "../Cellar/tool/1.0/bin/tool"
        )

        let tools = IntelInspector.tools(in: [bin.path(percentEncoded: false)])

        #expect(tools.map(\.name) == ["tool"])
        #expect(tools.map { PathPattern.comparablePath(of: $0.url) } == [PathPattern.comparablePath(of: program)])
    }

    /// Every Electron app keeps its helper processes under `Contents/Frameworks`, and Sparkle keeps its
    /// XPC services two levels down inside its framework. Those are processes, not libraries.
    @Test func findsTheHelperProcessesKeptUnderFrameworks() throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "Electron.app", cpuTypes: [intel, appleSilicon])
        _ = try bundle(directory, "Electron.app/Contents/Frameworks/Electron Helper (GPU).app", cpuTypes: [intel])
        _ = try bundle(directory, "Electron.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc", cpuTypes: [intel])
        _ = try bundle(directory, "Electron.app/Contents/Library/LaunchServices/com.example.helper.app", cpuTypes: [intel])
        // A library is loaded into the app, never run on its own.
        let library = try directory.file("Electron.app/Contents/Frameworks/libswiftCore.dylib", contents: fatHeader([intel]))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path(percentEncoded: false))

        let found = IntelInspector.intelOnlyBundles(inside: directory.url.appending(path: "Electron.app", directoryHint: .isDirectory))

        #expect(Set(found.map(\.lastPathComponent)) == ["Electron Helper (GPU).app", "Installer.xpc", "com.example.helper.app"])
    }

    /// A versioned framework keeps its services under `Versions/<letter>` and links to them from its top level
    /// (`XPCServices -> Versions/Current/XPCServices`, as Sparkle ships). Followed, the link would list each service
    /// twice, under two paths, so the top level is read only when it is a folder of its own.
    @Test func findsAFrameworksServiceOnceThroughItsLinks() throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "Updater.app", cpuTypes: [intel, appleSilicon])
        _ = try bundle(directory, "Updater.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc", cpuTypes: [intel])
        let framework = directory.url.appending(path: "Updater.app/Contents/Frameworks/Sparkle.framework")
        try FileManager.default.createSymbolicLink(atPath: framework.appending(path: "Versions/Current").path(percentEncoded: false), withDestinationPath: "B")
        try FileManager.default.createSymbolicLink(atPath: framework.appending(path: "XPCServices").path(percentEncoded: false), withDestinationPath: "Versions/Current/XPCServices")

        let found = IntelInspector.intelOnlyBundles(inside: directory.url.appending(path: "Updater.app", directoryHint: .isDirectory))

        #expect(found.filter { $0.lastPathComponent == "Installer.xpc" }.count == 1, "listed under \(found.map { $0.path(percentEncoded: false) })")
    }

    /// Two launchd jobs commonly run one program, and the list picks a row by its URL.
    @Test func reportsOneProgramOnceHoweverManyJobsRunIt() async throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("usr/local/bin/agent", contents: fatHeader([intel]))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: program.path(percentEncoded: false))
        func job(_ label: String) -> BackgroundItem {
            BackgroundItem(
                label: label, kind: .agent, source: .userLibrary, plistURL: nil,
                program: program.path(percentEncoded: false), runsAtLoad: false, keepsAlive: false,
                ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false,
                state: .loaded, isDisabled: false
            )
        }

        let scan = await IntelInspector.scan(
            installedApps: [],
            plugins: [],
            backgroundItems: [job("com.example.one"), job("com.example.two")],
            exclusions: .none,
            measure: { _ in 1 }
        )

        #expect(scan.findings.count == 1)
        #expect(Set(scan.findings.map(\.id)).count == 1)
    }

    /// Whatever sits where an executable is named gets opened, and a named pipe opened for reading waits for its
    /// other end. The Applications list and Intel Software would then never finish scanning.
    @Test func aPipeWhereAnExecutableShouldBeIsNotWaitedFor() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Pipe.app/Contents/MacOS")
        let pipe = folder.appending(path: "Pipe")
        try #require(mkfifo(pipe.path(percentEncoded: false), 0o755) == 0)

        #expect(MachOHeader.architectures(ofExecutableAt: pipe).isEmpty)
    }

    @Test func readsTheExecutableNamedInTheBundle() throws {
        let directory = try TemporaryDirectory()
        let app = try bundle(directory, "Intel.app", cpuTypes: [intel])
        let executable = try #require(IntelInspector.executable(of: app))
        #expect(executable.lastPathComponent == "Intel")
        #expect(IntelInspector.executable(of: directory.url.appending(path: "Missing.app")) == nil)
    }

    @Test func reportsIntelAppsWithTheirSize() async throws {
        let directory = try TemporaryDirectory()
        let appURL = try bundle(directory, "Intel.app", cpuTypes: [intel])
        let app = InstalledApp(
            url: appURL,
            bundleIdentifier: "com.example.intel",
            name: "Intel",
            architectures: [.x86_64]
        )

        let scan = await IntelInspector.scan(installedApps: [app])
        #expect(scan.findings.map(\.kind) == [.app])
        #expect(scan.findings.first?.name == "Intel")
        #expect(SizeTotal(scan.findings.map(\.size)).isComplete)
        #expect(SizeTotal(scan.findings.map(\.size)).known > 0)

        // An app that did not answer in time is still Intel only: it is listed, with a size nobody knows.
        let slow = await IntelInspector.scan(installedApps: [app], plugins: [], backgroundItems: [], exclusions: .none) { _ in nil }
        #expect(slow.findings.map(\.kind) == [.app])
        #expect(slow.findings.first?.size == nil)
        #expect(!SizeTotal(slow.findings.map(\.size)).isComplete)

        let excluded = await IntelInspector.scan(installedApps: [app], exclusions: Exclusions(bundleIdentifiers: ["com.example.intel"]))
        #expect(excluded.findings.isEmpty)
    }

    /// A library inside an app is loaded by that app, never run on its own. A common case is a bundled Swift
    /// runtime, which an arm64 Mac never loads.
    @Test func doesNotReportLibrariesBundledInsideAnApp() throws {
        let directory = try TemporaryDirectory()
        let app = directory.url.appending(path: "Universal.app")
        // Real Intel only binaries, executable, so they would be reported if the folder were searched.
        for path in ["Universal.app/Contents/Frameworks/libswiftCore.dylib", "Universal.app/Contents/Frameworks/Vendor.framework/Vendor"] {
            let library = try directory.file(path, contents: fatHeader([intel]))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: library.path(percentEncoded: false))
        }

        let found = IntelInspector.intelOnlyBundles(inside: app)

        #expect(found.isEmpty, "a library inside an app was reported: \(found.map(\.lastPathComponent))")
        #expect(!IntelInspector.embeddedDirectories.contains("Contents/Frameworks"))
    }
}
