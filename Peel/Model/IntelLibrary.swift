import Foundation
import Observation
import PeelCore

@Observable
final class IntelLibrary {
    private(set) var scan: IntelScan?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    /// The revision of the apps list the scan was made from. The page scans again when the list changes, so an
    /// app removed since does not stay listed.
    private(set) var scannedRevision: Int?
    var selection: IntelFinding.ID?

    var selectedFinding: IntelFinding? {
        scan?.findings.first { $0.id == selection }
    }

    var findings: [IntelFinding] { scan?.findings ?? [] }

    /// Scans everything the report covers, so it is complete even when the other pages were never opened.
    /// Plug-ins the Plug-ins page already found are reused, because that scan checks every plug-in's signature
    /// and a Mac used for music can hold hundreds of them.
    func refresh(installedApps: [InstalledApp], revision: Int, plugins known: [Plugin]? = nil) async {
        guard let result = await scanRun.run({
            let exclusions = ExclusionsStore.shared.exclusions
            async let backgroundItems = BackgroundItems.scan(exclusions: exclusions)
            let plugins = if let known { known } else { await Plugins.scan(exclusions: exclusions) }
            return await IntelInspector.scan(
                installedApps: installedApps,
                plugins: plugins,
                backgroundItems: backgroundItems.items,
                exclusions: exclusions
            )
        }) else { return }
        scan = result
        scannedRevision = revision
        if let selection, !result.findings.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}

extension IntelFinding.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .app: "Apps"
        case .insideApp: "Inside Universal Apps"
        case .plugin: "Plug-ins"
        case .driver: "Drivers"
        case .backgroundItem: "Background Items"
        case .commandLineTool: "Command Line Tools"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app.badge"
        case .insideApp: "shippingbox"
        case .plugin: "powerplug"
        case .driver: "printer"
        case .backgroundItem: "gearshape.2"
        case .commandLineTool: "terminal"
        }
    }

    /// Explains a finding. On an Intel Mac all of these run natively, so the text does not mention Rosetta.
    func explanation(onAppleSilicon: Bool) -> LocalizedStringResource {
        guard onAppleSilicon else {
            return switch self {
            case .app: "This app has no Apple silicon version. On this Intel Mac it runs natively."
            case .insideApp: "This part inside the app is Intel only. On this Intel Mac it runs natively."
            case .plugin: "This plug-in is Intel only. On this Intel Mac it loads natively."
            case .driver: "This driver is Intel only. On this Intel Mac it runs natively."
            case .backgroundItem: "This background item is Intel only. On this Intel Mac it runs natively."
            case .commandLineTool: "This tool in /usr/local is Intel only. On this Intel Mac it runs natively."
            }
        }
        return switch self {
        case .app: "This app has no Apple silicon version, so it needs Rosetta to run."
        case .insideApp: "This part inside the app is Intel only. It runs through Rosetta, or not at all."
        case .plugin: "This plug-in is Intel only, so it needs Rosetta to load."
        case .driver: "This driver is Intel only. The device it serves may stop working without Rosetta."
        case .backgroundItem: "This background item is Intel only, so it needs Rosetta to run."
        case .commandLineTool: "This tool in /usr/local is Intel only, so it needs Rosetta to run."
        }
    }
}
