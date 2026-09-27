import Foundation
import Observation
import PeelCore

@Observable
final class InstallerLibrary {
    private(set) var scan: InstallerScan?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    var selection: InstallerItem.Kind?
    var selectedURLs: Set<URL> = []

    var sections: [InstallerItem.Kind] {
        InstallerItem.Kind.allCases.filter { !items(in: $0).isEmpty }
    }

    func items(in kind: InstallerItem.Kind) -> [InstallerItem] {
        scan?.items(in: kind) ?? []
    }

    var needsFullDiskAccess: Bool {
        scan?.needsFullDiskAccess ?? false
    }

    func refresh(installedApps: [InstalledApp]) async {
        guard let result = await scanRun.run({ await Installers.scan(installedApps: installedApps, exclusions: ExclusionsStore.shared.exclusions) }) else { return }
        scan = result
        selectedURLs.formIntersection(Set(result.items.filter { $0.heldBack?.cannotBeMoved != true }.map(\.url)))
        if let selection, result.items(in: selection).isEmpty {
            self.selection = nil
        }
    }

    private func selected(in kind: InstallerItem.Kind) -> [InstallerItem] {
        items(in: kind).filter { !$0.isReadOnly && selectedURLs.contains($0.url) }
    }
}

extension InstallerLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        sections.compactMap { kind in
            let selected = selected(in: kind)
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: Tool.installers.page(kind.rawValue),
                title: String(localized: kind.title),
                source: kind.title.inEnglish,
                sourceKey: "installers.\(kind.rawValue)",
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let kind = InstallerItem.Kind(rawValue: part.page.scope) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let selected = selected(in: kind).filter { part.sizes.keys.contains($0.url) }
        let privileged = Set(selected.filter(\.requiresPrivileges).map(\.url))
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions)
            .trash(selected.map(\.url), usingHelperFor: privileged)
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh(installedApps: apps.apps)
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = InstallerItem.Kind(rawValue: page.scope)
    }
}

extension InstallerItem.Kind {
    var title: LocalizedStringResource {
        switch self {
        case .appInstaller: "App Installers"
        case .macOSInstaller: "macOS Installers"
        case .firmware: "Device Firmware"
        case .deviceBackup: "iPhone and iPad Backups"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .appInstaller: "Disk images and packages at the top of Downloads, Desktop, and Documents, where installers are usually left. A disk image can also be one you made to keep files in. What an installer installed stays where it is."
        case .macOSInstaller: "A full copy of macOS, ready to install. Apple offers the newest release again to any Mac that can run it."
        case .firmware: "Firmware for restoring Apple devices, such as an iPhone, an iPad, or a Mac. It is downloaded again when a device needs it."
        case .deviceBackup: "Almost all of a device’s data and settings, backed up to this Mac. Peel shows what is here and leaves the rest to Finder."
        }
    }

    var systemImage: String {
        switch self {
        case .appInstaller: "arrow.down.app"
        case .macOSInstaller: "apple.logo"
        case .firmware: "iphone.gen3"
        case .deviceBackup: "externaldrive"
        }
    }
}
