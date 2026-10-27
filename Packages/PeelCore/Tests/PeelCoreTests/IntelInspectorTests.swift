import Foundation
@testable import PeelCore
import Synchronization
import Testing

struct IntelInspectorTests {
    /// A fat header listing the given CPU types, which is all the reader looks at.
    private func fatHeader(_ cpuTypes: [UInt32]) -> Data {
        var bytes: [UInt8] = []
        func append(_ value: UInt32) {
            bytes += [
                UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF),
            ]
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

    @Test func findsAnIntelProgramWhoseFileStartsWithItsI386Slice() throws {
        let directory = try TemporaryDirectory()
        var bytes = Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x02])
        for (cpuType, offset) in [(UInt32(7), UInt32(4_096)), (intel, UInt32(8_192))] {
            for value in [cpuType, 3, offset, 4_096, 12] {
                bytes += [24, 16, 8, 0].map { UInt8(value >> $0 & 0xFF) }
            }
        }
        bytes += Data(count: 4_096 - bytes.count)
        bytes += Data([0xCE, 0xFA, 0xED, 0xFE, 0x07, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00])
        bytes += Data(count: 8_192 - bytes.count)
        bytes += intelHeader(fileType: 2)
        bytes += Data(count: 12_288 - bytes.count)
        let filter = try directory.file("Printers/Vendor/filter", contents: bytes)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: filter.path(percentEncoded: false)
        )
        let printers = directory.url.appending(path: "Printers").path(percentEncoded: false)

        #expect(MachOHeader.isProgram(at: filter) == true)
        #expect(readable { IntelInspector.programs(in: [printers], unreadable: &$0) }.map(\.lastPathComponent) == ["filter"])
    }

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
            _ = await IntelInspector.scan(
                installedApps: installed,
                exclusions: .none,
                environment: environment,
                measure: unanswered.measure
            )
        }

        #expect(stop.took < .seconds(1))
        #expect(stop.askedBefore < 30)
        #expect(stop.askedAfter == 0)
    }

    /// A printer's folder can hold thousands of files, so a stopped scan stops walking it.
    @Test func aStoppedScanStopsWalkingDriverFolders() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...3 {
            _ = try bundle(directory, "Printers/Driver \(index).driver", cpuTypes: [intel])
            let filter = try directory.file("Printers/Filters/filter\(index)", contents: intelHeader(fileType: 2))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: filter.path(percentEncoded: false)
            )
        }
        let printers = directory.url.appending(path: "Printers").path(percentEncoded: false)

        let walked = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let bundles = readable { IntelInspector.bundles(in: [printers], unreadable: &$0) }
            return (bundles, readable { IntelInspector.programs(in: [printers], unreadable: &$0) })
        }.value

        #expect(readable { IntelInspector.bundles(in: [printers], unreadable: &$0) }.count == 3)
        #expect(readable { IntelInspector.programs(in: [printers], unreadable: &$0) }.count == 3)
        #expect(walked.0.isEmpty)
        #expect(walked.1.isEmpty)
    }

    @Test func walksTheFolderAfterAFileNamedLikeABundle() throws {
        let directory = try TemporaryDirectory()
        try directory.file("Printers/Backup.bundle", bytes: 16)
        for folder in ["Filters", "Tools", "Utilities", "Scripts", "Helpers"] {
            let filter = try directory.file("Printers/\(folder)/filter", contents: intelHeader(fileType: 2))
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: filter.path(percentEncoded: false)
            )
        }
        let printers = directory.url.appending(path: "Printers").path(percentEncoded: false)

        let folders = readable { IntelInspector.programs(in: [printers], unreadable: &$0) }
            .map { $0.deletingLastPathComponent().lastPathComponent }

        #expect(folders.sorted() == ["Filters", "Helpers", "Scripts", "Tools", "Utilities"])
    }

    private func bundle(_ directory: borrowing TemporaryDirectory, _ path: String, cpuTypes: [UInt32]) throws -> URL {
        let name = (path as NSString).lastPathComponent
        let executableName = (name as NSString).deletingPathExtension
        let executable = try directory.file("\(path)/Contents/MacOS/\(executableName)", contents: fatHeader(cpuTypes))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path(percentEncoded: false)
        )
        try directory.file("\(path)/Contents/Info.plist", contents: Data("<plist></plist>".utf8))
        return directory.url.appending(path: path, directoryHint: .isDirectory)
    }

    /// Runs one of the scan's walks over fixtures that can all be read, so it names nothing it couldn't read.
    private func readable<T>(_ walk: (inout [URL]) -> T) -> T {
        var unread: [URL] = []
        defer { #expect(unread.isEmpty, "named \(unread)") }
        return walk(&unread)
    }

    private func environment(in directory: borrowing TemporaryDirectory) -> SearchEnvironment {
        SearchEnvironment(
            homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
            rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
        )
    }

    @Test func countsWhatItReadsForThePagesFigure() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...3 {
            _ = try bundle(directory, "root/Library/Printers/Vendor/Driver \(index).plugin", cpuTypes: [appleSilicon])
        }
        let count = ScanCount()

        _ = await ScanCount.$current.withValue(count) {
            await IntelInspector.scan(
                installedApps: [], exclusions: .none, environment: environment(in: directory), measure: { _ in 1 }
            )
        }

        #expect(count.value > 0, "the page's figure stood still while Intel Software read")
    }

    @Test func measuresSeveralFindingsAtOnce() async throws {
        let directory = try TemporaryDirectory()
        for index in 1...6 {
            _ = try bundle(directory, "root/Library/Printers/Driver \(index).plugin", cpuTypes: [intel])
        }
        let inFlight = Mutex((now: 0, most: 0))

        let scan = await IntelInspector.scan(
            installedApps: [], exclusions: .none, environment: environment(in: directory)
        ) { _ in
            inFlight.withLock {
                $0.now += 1
                $0.most = max($0.most, $0.now)
            }
            await Task.yield()
            inFlight.withLock { $0.now -= 1 }
            return 1
        }

        #expect(scan.findings.count == 6)
        #expect(inFlight.withLock { $0.most } > 1, "each measurement waited for the one before")
    }

    @Test func takesAnAppsSizeFromTheApplicationsList() async throws {
        let directory = try TemporaryDirectory()
        let url = try bundle(directory, "Apps/Old.app", cpuTypes: [intel])
        let app = InstalledApp(url: url, bundleIdentifier: "org.example.old", name: "Old", architectures: [.x86_64])
        let measured = Mutex<[URL]>([])

        let scan = await IntelInspector.scan(
            installedApps: [app], knownSizes: [url: 42], exclusions: .none, environment: environment(in: directory)
        ) { url in
            measured.withLock { $0.append(url) }
            return 1
        }

        #expect(scan.findings.map(\.size) == [42])
        #expect(measured.withLock { $0 }.isEmpty, "Applications had measured it already")
    }

    @Test func tellsIntelOnlyBundlesFromUniversalOnes() throws {
        let directory = try TemporaryDirectory()
        let intelApp = try bundle(directory, "Intel.app", cpuTypes: [intel])
        let universalApp = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        let appleApp = try bundle(directory, "Apple.app", cpuTypes: [appleSilicon])

        #expect(readable { IntelInspector.isIntelOnly(bundle: intelApp, unreadable: &$0) })
        #expect(!readable { IntelInspector.isIntelOnly(bundle: universalApp, unreadable: &$0) })
        #expect(!readable { IntelInspector.isIntelOnly(bundle: appleApp, unreadable: &$0) })
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
            exclusions: .none,
            environment: SearchEnvironment(homeDirectory: home, rootDirectory: root),
            measure: { _ in 1 }
        )

        #expect(Set(scan.findings.map(\.name)) == ["Melody.bundle", "Vendor.plugin"])
        #expect(scan.findings.first { $0.name == "Melody.bundle" }?.kind == .plugin, "an ARA plug-in serves no device")
        #expect(scan.findings.first { $0.name == "Vendor.plugin" }?.kind == .driver)
    }

    @Test func findsAnIntelTWAINDataSource() async throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "root/Library/Image Capture/TWAIN Data Sources/Scanner.ds", cpuTypes: [intel])

        let scan = await IntelInspector.scan(
            installedApps: [],
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
            exclusions: .none,
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            measure: { _ in 1 }
        )

        // A HAL driver sits in a folder of plug-ins too, and is listed as the Plug-ins page lists it.
        let kinds = Dictionary(uniqueKeysWithValues: scan.findings.map { ($0.name, $0.kind) })
        #expect(kinds == ["rastertovendor": .driver, "Port.driver": .driver, "Device": .plugin])
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
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: plainHelper.path(percentEncoded: false)
        )

        let found = readable {
            IntelInspector.intelOnlyBundles(
                inside: directory.url.appending(path: "Universal.app", directoryHint: .isDirectory), unreadable: &$0
            )
        }
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
        let found = readable { IntelInspector.intelOnlyBundles(inside: app, unreadable: &$0) }

        #expect(Set(found.map(\.lastPathComponent)) == [
            "ffmpeg", "Preview.qlgenerator", "Importer.mdimporter", "Filter.systemextension",
        ])
    }

    @Test func findsTheUpdatersAnAppKeepsBesideItsFrameworksAndResources() throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        let sparkle = "Universal.app/Contents/Frameworks/Sparkle.framework"
        let squirrel = "Universal.app/Contents/Frameworks/Squirrel.framework"
        _ = try bundle(directory, "\(sparkle)/Versions/B/Updater.app", cpuTypes: [intel])
        try directory.setPermissions(0o755, of: try directory.file("\(sparkle)/Versions/B/Autoupdate", contents: intelHeader(fileType: 2)))
        // The framework's own library loads into the app's process.
        try directory.setPermissions(0o755, of: try directory.file("\(sparkle)/Versions/B/Sparkle", contents: intelHeader(fileType: 6)))
        try directory.setPermissions(0o755, of: try directory.file("\(squirrel)/Versions/A/Resources/ShipIt", contents: intelHeader(fileType: 2)))
        try directory.file("\(squirrel)/Versions/A/Resources/Info.plist", bytes: 16)
        for (link, destination) in [
            ("\(sparkle)/Versions/Current", "B"), ("\(sparkle)/Autoupdate", "Versions/Current/Autoupdate"),
            ("\(sparkle)/Updater.app", "Versions/Current/Updater.app"), ("\(squirrel)/Versions/Current", "A"),
            ("\(squirrel)/Resources", "Versions/Current/Resources"),
        ] {
            try FileManager.default.createSymbolicLink(
                atPath: directory.url.appending(path: link).path(percentEncoded: false),
                withDestinationPath: destination
            )
        }
        try directory.setPermissions(0o755, of: try directory.file("Universal.app/Contents/Resources/helper", contents: intelHeader(fileType: 2)))
        try directory.file("Universal.app/Contents/Resources/strings.pak", bytes: 16)
        _ = try bundle(directory, "Universal.app/Contents/Resources/Loaded.bundle", cpuTypes: [intel])
        _ = try bundle(directory, "Universal.app/Contents/SharedSupport/Installer.app", cpuTypes: [intel])

        let app = directory.url.appending(path: "Universal.app", directoryHint: .isDirectory)
        let found = readable { IntelInspector.intelOnlyBundles(inside: app, unreadable: &$0) }

        #expect(found.map(\.lastPathComponent).sorted() == ["Autoupdate", "Installer.app", "ShipIt", "Updater.app", "helper"])
    }

    @Test func readsOnlyTheBundlesAFrameworkKeepsWhenOnlyBundlesAreAsked() throws {
        let directory = try TemporaryDirectory()
        let version = "Universal.app/Contents/Frameworks/Sparkle.framework/Versions/B"
        _ = try bundle(directory, "\(version)/Updater.app", cpuTypes: [intel])
        try directory.setPermissions(0o755, of: try directory.file("\(version)/Autoupdate", contents: intelHeader(fileType: 2)))
        let app = directory.url.appending(path: "Universal.app", directoryHint: .isDirectory)

        let bundles = readable { IntelInspector.frameworkProcesses(inside: app, bundlesOnly: true, unreadable: &$0) }
        let everything = readable { IntelInspector.frameworkProcesses(inside: app, unreadable: &$0) }

        #expect(bundles.map(\.lastPathComponent) == ["Updater.app"])
        #expect(everything.map(\.lastPathComponent).sorted() == ["Autoupdate", "Updater.app"])
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

        let tools = readable { IntelInspector.tools(in: [bin.path(percentEncoded: false)], unreadable: &$0) }

        #expect(tools.map(\.name) == ["tool"])
        #expect(tools.map { PathPattern.comparablePath(of: $0.url) } == [PathPattern.comparablePath(of: program)])
    }

    @Test func looksForCommandsUnderTheRootItIsGiven() async throws {
        let directory = try TemporaryDirectory()
        let tool = try directory.file("root/usr/local/bin/tool", contents: fatHeader([intel]))
        try directory.setPermissions(0o755, of: tool)

        let scan = await IntelInspector.scan(
            installedApps: [],
            exclusions: .none,
            environment: SearchEnvironment(
                homeDirectory: directory.url.appending(path: "home", directoryHint: .isDirectory),
                rootDirectory: directory.url.appending(path: "root", directoryHint: .isDirectory)
            ),
            measure: { _ in 1 }
        )

        #expect(scan.findings.map(\.name) == ["tool"])
        #expect(scan.findings.allSatisfy { $0.kind == .commandLineTool })
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
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: library.path(percentEncoded: false)
        )

        let found = readable {
            IntelInspector.intelOnlyBundles(
                inside: directory.url.appending(path: "Electron.app", directoryHint: .isDirectory), unreadable: &$0
            )
        }

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
        try FileManager.default.createSymbolicLink(
            atPath: framework.appending(path: "Versions/Current").path(percentEncoded: false),
            withDestinationPath: "B"
        )
        try FileManager.default.createSymbolicLink(
            atPath: framework.appending(path: "XPCServices").path(percentEncoded: false),
            withDestinationPath: "Versions/Current/XPCServices"
        )

        let found = readable {
            IntelInspector.intelOnlyBundles(
                inside: directory.url.appending(path: "Updater.app", directoryHint: .isDirectory), unreadable: &$0
            )
        }

        #expect(found.filter { $0.lastPathComponent == "Installer.xpc" }.count == 1, "listed under \(found.map { $0.path(percentEncoded: false) })")
    }

    /// Two launchd jobs commonly run one program, and the list picks a row by its URL.
    @Test func reportsOneProgramOnceHoweverManyJobsRunIt() async throws {
        let directory = try TemporaryDirectory()
        let program = try directory.file("usr/local/bin/agent", contents: fatHeader([intel]))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: program.path(percentEncoded: false)
        )
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
            backgroundItems: BackgroundItems.Scan(items: [job("com.example.one"), job("com.example.two")]),
            exclusions: .none,
            environment: environment(in: directory),
            measure: { _ in 1 }
        )

        #expect(scan.findings.count == 1)
        #expect(Set(scan.findings.map(\.id)).count == 1)
        #expect(scan.findings.first?.job == job("com.example.one").id, "Background Items couldn't show its row")
    }

    /// Whatever sits where an executable is named gets opened, and a named pipe opened for reading waits for its
    /// other end. The Applications list and Intel Software would then never finish scanning.
    @Test func aPipeWhereAnExecutableShouldBeIsNotWaitedFor() throws {
        let directory = try TemporaryDirectory()
        let folder = try directory.directory("Pipe.app/Contents/MacOS")
        let pipe = folder.appending(path: "Pipe")
        try #require(mkfifo(pipe.path(percentEncoded: false), 0o755) == 0)

        #expect(MachOHeader.architectures(ofExecutableAt: pipe) == [])
    }

    @Test func readsTheExecutableNamedInTheBundle() throws {
        let directory = try TemporaryDirectory()
        let app = try bundle(directory, "Intel.app", cpuTypes: [intel])
        let executable = try #require(readable { IntelInspector.executable(of: app, unreadable: &$0) })
        #expect(executable.lastPathComponent == "Intel")
        #expect(readable { IntelInspector.executable(of: directory.url.appending(path: "Missing.app"), unreadable: &$0) } == nil)
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

        let scan = await IntelInspector.scan(installedApps: [app], environment: environment(in: directory))
        #expect(scan.findings.map(\.kind) == [.app])
        #expect(scan.findings.first?.name == "Intel")
        #expect(SizeTotal(scan.findings.map(\.size)).isComplete)
        #expect(SizeTotal(scan.findings.map(\.size)).known > 0)

        // An app that did not answer in time is still Intel only: it is listed, with a size nobody knows.
        let slow = await IntelInspector.scan(
            installedApps: [app],
            exclusions: .none,
            environment: environment(in: directory)
        ) { _ in nil }
        #expect(slow.findings.map(\.kind) == [.app])
        #expect(slow.findings.first?.size == nil)
        #expect(!SizeTotal(slow.findings.map(\.size)).isComplete)

        let excluded = await IntelInspector.scan(
            installedApps: [app],
            exclusions: Exclusions(bundleIdentifiers: ["com.example.intel"]),
            environment: environment(in: directory)
        )
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
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: library.path(percentEncoded: false)
            )
        }

        let found = readable { IntelInspector.intelOnlyBundles(inside: app, unreadable: &$0) }

        #expect(found.isEmpty, "a library inside an app was reported: \(found.map(\.lastPathComponent))")
        #expect(!IntelInspector.embeddedDirectories.contains("Contents/Frameworks"))
    }

    @Test func countsCodeOnceThoughAJobOrACommandRunsIt() async throws {
        let directory = try TemporaryDirectory()
        let intelApp = try bundle(directory, "Apps/Intel.app", cpuTypes: [intel])
        let agent = try directory.file("Apps/Intel.app/Contents/MacOS/Agent", contents: intelHeader(fileType: 2))
        try directory.setPermissions(0o755, of: agent)
        let universal = try bundle(directory, "Apps/Universal.app", cpuTypes: [intel, appleSilicon])
        let helper = try bundle(directory, "Apps/Universal.app/Contents/Library/LoginItems/Helper.app", cpuTypes: [intel])
        func job(_ label: String, running program: URL) -> BackgroundItem {
            BackgroundItem(
                label: label, kind: .agent, source: .userLibrary, plistURL: nil,
                program: program.path(percentEncoded: false), runsAtLoad: true, keepsAlive: false,
                ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false, state: .loaded,
                isDisabled: false
            )
        }
        let bin = try directory.directory("root/usr/local/bin")
        try FileManager.default.createSymbolicLink(
            at: bin.appending(path: "helper"), withDestinationURL: helper.appending(path: "Contents/MacOS/Helper")
        )

        let scan = await IntelInspector.scan(
            installedApps: [
                InstalledApp(url: intelApp, bundleIdentifier: "org.example.intel", name: "Intel", architectures: [.x86_64]),
                InstalledApp(url: universal, bundleIdentifier: "org.example.universal", name: "Universal", architectures: [.x86_64, .arm64]),
            ],
            backgroundItems: BackgroundItems.Scan(items: [
                job("org.example.intel.agent", running: agent),
                job("org.example.universal.helper", running: helper.appending(path: "Contents/MacOS/Helper")),
            ]),
            exclusions: .none,
            environment: environment(in: directory),
            measure: { _ in 1 }
        )

        let rows = Dictionary(uniqueKeysWithValues: scan.findings.map { ($0.name, ($0.kind, $0.backgroundItems)) })
        #expect(rows.count == 2, "listed \(scan.findings.map(\.name))")
        #expect(rows["Intel"]?.0 == .app)
        #expect(rows["Intel"]?.1 == ["org.example.intel.agent"])
        #expect(rows["Helper.app"]?.0 == .insideApp)
        #expect(rows["Helper.app"]?.1 == ["org.example.universal.helper"])
        #expect(scan.findings.filter { $0.matches("intel.agent") }.map(\.name) == ["Intel"])
    }

    @Test func readsThePlugInFoldersItself() async throws {
        let directory = try TemporaryDirectory()
        _ = try bundle(directory, "home/Library/Audio/Plug-Ins/VST3/Old.vst3", cpuTypes: [intel])
        _ = try bundle(directory, "root/Library/Audio/Plug-Ins/Components/New.component", cpuTypes: [intel, appleSilicon])

        let scan = await IntelInspector.scan(
            installedApps: [], exclusions: .none, environment: environment(in: directory), measure: { _ in 1 }
        )

        #expect(scan.findings.map(\.name) == ["Old"])
        #expect(scan.findings.map(\.kind) == [.plugin])
        #expect(scan.findings.map(\.pluginCategory) == [.vst3])
    }

    @Test(.permissionsHold) func namesWhatItCouldNotRead() async throws {
        let directory = try TemporaryDirectory()
        let closedDrivers = try directory.directory("root/Library/Printers/Closed")
        let hiddenFilter = try directory.file("root/Library/Printers/Closed/filter", contents: intelHeader(fileType: 2))
        try directory.setPermissions(0o755, of: hiddenFilter)
        let groupsFilter = try directory.file("root/Library/Printers/Vendor/filter", contents: intelHeader(fileType: 2))
        let tool = try directory.file("root/usr/local/bin/tool", contents: fatHeader([intel]))
        let agent = try directory.file("Agents/agent", contents: fatHeader([intel]))
        let universal = try bundle(directory, "Universal.app", cpuTypes: [intel, appleSilicon])
        _ = try bundle(directory, "Universal.app/Contents/Library/LoginItems/Launcher.app", cpuTypes: [intel])
        let closedLibrary = universal.appending(path: "Contents/Library", directoryHint: .isDirectory)
        let closedApp = try bundle(directory, "Closed.app", cpuTypes: [intel])
        let closedProgram = closedApp.appending(path: "Contents/MacOS/Closed")
        try directory.setPermissions(0o010, of: groupsFilter)
        for program in [tool, agent, closedProgram] { try directory.setPermissions(0o311, of: program) }
        let plugInFolder = try directory.directory("home/Library/Audio/Plug-Ins/VST3/Vendor")
        _ = try bundle(directory, "home/Library/Audio/Plug-Ins/VST3/Vendor/Old.vst3", cpuTypes: [intel])
        let closed = [closedDrivers, closedLibrary, plugInFolder]
        for folder in closed { try directory.setPermissions(0o000, of: folder) }
        defer { for folder in closed { try? directory.setPermissions(0o755, of: folder) } }
        let job = BackgroundItem(
            label: "org.example.agent", kind: .agent, source: .userLibrary, plistURL: nil,
            program: agent.path(percentEncoded: false), runsAtLoad: false, keepsAlive: false,
            ownerBundleIdentifier: nil, ownerName: nil, ownerURL: nil, isOrphan: false, state: .loaded,
            isDisabled: false
        )

        let scan = await IntelInspector.scan(
            installedApps: [
                InstalledApp(url: universal, bundleIdentifier: "org.example.universal", name: "Universal", architectures: [.x86_64, .arm64]),
                InstalledApp(url: closedApp, bundleIdentifier: "org.example.closed", name: "Closed", architectures: []),
            ],
            backgroundItems: BackgroundItems.Scan(items: [job], unanswered: .init(lists: [.daemon])),
            exclusions: .none,
            environment: environment(in: directory),
            measure: { _ in 1 }
        )

        #expect(scan.findings.isEmpty, "found \(scan.findings.map(\.name))")
        let expected = [closedDrivers, groupsFilter, tool, agent, closedLibrary, closedProgram, plugInFolder]
        let named = scan.unreadable.map(PathPattern.comparablePath(of:)).sorted()
        #expect(named == expected.map(PathPattern.comparablePath(of:)).sorted())
        #expect(!scan.needsFullDiskAccess)
        #expect(scan.unansweredJobs == [.daemon])
    }

    @Test func namesTheJobFilesItCouldNotRead() async throws {
        let directory = try TemporaryDirectory()
        let daemons = directory.url.appending(path: "root/Library/LaunchDaemons", directoryHint: .isDirectory)
        let agents = directory.url.appending(path: "home/Library/LaunchAgents", directoryHint: .isDirectory)
        func job(_ label: String) -> BackgroundItem {
            BackgroundItem(
                label: label, kind: .daemon, source: .systemLibrary, plistURL: daemons.appending(path: "\(label).plist"),
                program: nil, runsAtLoad: nil, keepsAlive: nil, ownerBundleIdentifier: nil, ownerName: nil,
                ownerURL: nil, isOrphan: false, state: .notLoaded, isDisabled: false
            )
        }
        var closed = job("org.example.closed")
        closed.isClosedToPeel = true
        closed.isNamedByItsFile = true
        var broken = job("org.example.broken")
        broken.isUnreadable = true
        broken.isNamedByItsFile = true

        let scan = await IntelInspector.scan(
            installedApps: [],
            backgroundItems: BackgroundItems.Scan(items: [closed, broken], unreadableFolders: [agents]),
            exclusions: .none,
            environment: environment(in: directory),
            measure: { _ in 1 }
        )

        let named = scan.unreadable.map(PathPattern.comparablePath(of:)).sorted()
        let expected = [daemons.appending(path: "org.example.closed.plist"), agents]
        #expect(named == expected.map(PathPattern.comparablePath(of:)).sorted(), "what launchd can't load runs nothing")
    }
}
