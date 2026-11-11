import Foundation
import Observation
import PeelCore

@Observable
final class IntelLibrary {
    private(set) var scan: IntelScan?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    var selection: IntelFinding.ID?

    var selectedFinding: IntelFinding? {
        scan?.findings.first { $0.id == selection }
    }

    var findings: [IntelFinding] { scan?.findings ?? [] }

    /// Reads the page from the installed apps, the sizes the Applications list measured, and the exclusions.
    typealias Read = @MainActor ([InstalledApp], [URL: Int64], Exclusions) async -> IntelScan

    private let read: Read

    /// `read` scans everything the report covers, so it is complete even when the other pages were never opened.
    init(
        read: @escaping Read = { installedApps, sizes, exclusions in
            async let backgroundItems = BackgroundItems.scan(installedApps: installedApps, exclusions: exclusions)
            return await IntelInspector.scan(
                installedApps: installedApps,
                knownSizes: sizes,
                backgroundItems: backgroundItems,
                exclusions: exclusions
            )
        }
    ) {
        self.read = read
    }

    func refresh(installedApps: [InstalledApp], knownSizes: [URL: Int64]) async {
        let read = read
        guard let result = await scanRun.run({
            await read(installedApps, knownSizes, ExclusionsStore.shared.exclusions)
        }) else { return }
        show(result)
    }

    /// Reads the page again without showing a scan, once it has been read.
    func readAgain(installedApps: [InstalledApp], knownSizes: [URL: Int64]) async {
        guard scan != nil else { return }
        let read = read
        guard let result = await scanRun.runQuietly({
            await read(installedApps, knownSizes, ExclusionsStore.shared.exclusions)
        }) else { return }
        show(result)
    }

    private func show(_ result: IntelScan) {
        scan = result
        if let selection, !result.findings.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}

extension IntelFinding.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .app: "Apps"
        case .insideApp: "Inside Other Apps"
        case .plugin: "Plug-ins"
        case .driver: "Drivers"
        case .backgroundItem: "Background Items"
        case .commandLineTool: "Command-Line Tools"
        case .javaRuntime: "Java Runtimes"
        }
    }

    /// Whether opening it is a way to install Rosetta: macOS offers to the first time an Intel app opens.
    var offersRosettaWhenOpened: Bool { self == .app }

    var systemImage: String {
        switch self {
        case .app: "app.badge"
        case .insideApp: "shippingbox"
        case .plugin: "powerplug"
        case .driver: "printer"
        case .backgroundItem: "gearshape.2"
        case .commandLineTool: "terminal"
        case .javaRuntime: "cup.and.saucer"
        }
    }

    /// Explains a finding. On an Intel Mac all of these run natively, so the text does not mention Rosetta.
    func explanation(onAppleSilicon: Bool) -> LocalizedStringResource {
        guard onAppleSilicon else {
            return switch self {
            case .app: "This copy is built for Intel only. On this Intel Mac it runs natively."
            case .insideApp: "This part inside the app is Intel only. On this Intel Mac it runs natively."
            case .plugin: "This plug-in is Intel only. On this Intel Mac it loads natively."
            case .driver: "This driver is Intel only. On this Intel Mac it runs natively."
            case .backgroundItem: "This background item is Intel only. On this Intel Mac it runs natively."
            case .commandLineTool: "This tool in /usr/local is Intel only. On this Intel Mac it runs natively."
            case .javaRuntime: "This Java runtime is Intel only. On this Intel Mac it runs natively."
            }
        }
        return switch self {
        case .app:
            "This copy is built for Intel only, so it needs Rosetta to run. If its maker offers a version for Apple silicon, install that one instead."
        case .insideApp: "This part inside the app is Intel only. It runs through Rosetta, or not at all."
        case .plugin: "This plug-in is Intel only, so it needs Rosetta to load."
        case .driver: "This driver is Intel only. The device it serves may stop working without Rosetta."
        case .backgroundItem: "This background item is Intel only, so it needs Rosetta to run."
        case .commandLineTool: "This tool in /usr/local is Intel only, so it needs Rosetta to run."
        case .javaRuntime:
            "This Java runtime is Intel only, so it needs Rosetta to run. If its maker offers one for Apple silicon, install that one instead."
        }
    }
}

extension IntelFinding.CommandFolder {
    /// Nil for `/usr/local`'s, which the kind explains.
    func explanation(onAppleSilicon: Bool) -> LocalizedStringResource? {
        switch self {
        case .usrLocal: nil
        case .macPorts:
            onAppleSilicon
                ? "This tool from MacPorts is Intel only, so it needs Rosetta to run. MacPorts reinstalls its ports for this Mac with `sudo port migrate`."
                : "This tool from MacPorts is Intel only. On this Intel Mac it runs natively."
        case .home:
            onAppleSilicon
                ? "This tool in your home folder is Intel only, so it needs Rosetta to run. If its maker offers a version for Apple silicon, install that one instead."
                : "This tool in your home folder is Intel only. On this Intel Mac it runs natively."
        }
    }
}

extension IntelFinding {
    /// Explains the finding, a plug-in by where its Intel code can load (`Plugin.Category.intelHost`).
    func explanation(onAppleSilicon: Bool) -> LocalizedStringResource {
        if prefersIntel {
            return "This app has a version for Apple silicon, but it asks macOS to open it as an Intel app, so it runs through Rosetta."
        }
        if noLongerLoaded != nil {
            return kind == .insideApp
                ? "This part inside the app is Intel only, and macOS no longer loads parts of its kind, with or without Rosetta."
                : "This plug-in is Intel only, and macOS no longer loads plug-ins of its kind, with or without Rosetta."
        }
        if kind == .commandLineTool, let words = commandFolder?.explanation(onAppleSilicon: onAppleSilicon) {
            return words
        }
        guard onAppleSilicon, kind == .plugin else { return kind.explanation(onAppleSilicon: onAppleSilicon) }
        return switch pluginCategory?.intelHost {
        case .insideTheApp:
            "This plug-in is Intel only. It loads only inside an app that itself runs through Rosetta."
        case .outsideTheAppWhenAsked:
            "This plug-in is Intel only. It loads only in an app that runs through Rosetta, or that asks macOS to load it in a process of its own."
        default:
            kind.explanation(onAppleSilicon: onAppleSilicon)
        }
    }

    /// The name of what the page's badge says, and its note.
    var badge: (title: LocalizedStringResource, detail: LocalizedStringResource) {
        prefersIntel
            ? ("Opens as Intel", "Built for both. Its Info.plist asks macOS to open it as an Intel app, so on Apple silicon it runs through Rosetta.")
            : ("Intel only", "Built for Intel processors only. On Apple silicon it needs Rosetta.")
    }

    /// What the page says of a Mac without Rosetta: only what is sure of an app that also has a version for Apple
    /// silicon, since what macOS then opens isn't documented.
    var withoutRosetta: LocalizedStringResource {
        prefersIntel
            ? "Rosetta isn’t installed on this Mac, so its Intel version can’t run here."
            : "Rosetta isn’t installed on this Mac, so this doesn’t run at all. macOS offers to install it the first time you open an Intel app, and macOS 27 is the last release that runs most Intel software through it."
    }

    /// What the row says under the name: what the finding belongs to, the job file that starts a background item, or
    /// a plug-in's format, since one plug-in is often installed in several formats under one name.
    var subtitle: LocalizedStringResource? {
        guard let owner else { return pluginCategory?.title }
        return kind == .backgroundItem ? "started by \(owner)" : "in \(owner)"
    }

    /// Whether the Plug-ins page lists it: a plug-in found in one of that page's folders, which carries its format.
    var isOnThePlugInsPage: Bool {
        kind == .plugin && pluginCategory != nil
    }

    /// Whether an app that loads the plug-in decides whether it loads, as for a plug-in loaded inside the app.
    var loadsThroughAnApp: Bool {
        kind == .plugin && [.insideTheApp, .outsideTheAppWhenAsked].contains(pluginCategory?.intelHost)
    }
}
