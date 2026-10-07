import AppKit
import Foundation
import Observation
import PeelCore

/// One project folder and everything a build left inside it.
struct ProjectGroup: Identifiable, Hashable {
    let project: URL
    let artifacts: [ProjectArtifact]

    var id: URL { project }
    var page: CarriedSelection.Page { Tool.projects.page(project.path(percentEncoded: false)) }
    var total: SizeTotal { SizeTotal(artifacts.map(\.size)) }
    var lastChange: ProjectArtifacts.LastChange { ProjectArtifacts.lastChange(of: artifacts) }
}

@Observable
final class ProjectLibrary {
    private static let foldersKey = "projectFolders"

    private(set) var groups: [ProjectGroup]?
    /// The scan this page runs, which a newer one or the Stop button ends.
    let scanRun = ScanRun()
    var isScanning: Bool { scanRun.isRunning }
    private(set) var isRemoving = false
    private(set) var folders: [URL]
    /// Which artifacts Time Machine is already leaving out.
    private(set) var excludedFromBackups: Set<URL> = []
    /// Artifacts excluded from backups by a folder above them or by a path rule. The exclusion is not their
    /// own, so it cannot be removed from here.
    private(set) var excludedFromAbove: Set<URL> = []
    /// The folders that would not take the mark the last time Peel changed it on them, whichever project they are in.
    private var backupMarkFailures: Set<URL> = []
    /// True when the scan reached its limit on how many folders it reads, so the list may be incomplete.
    private(set) var wasCutShort = false
    private(set) var needsFullDiskAccess = false
    /// The folders the last scan could not read, so what they hold isn't known.
    private(set) var unreadable: [URL] = []
    /// Folders the last Add refused, with the reason, until the next one.
    private(set) var refused: [(url: URL, reason: ProjectArtifacts.Refusal)] = []
    var selection: URL?
    var selectedURLs: Set<URL> = []

    init() {
        folders = (UserDefaults.standard.array(forKey: Self.foldersKey) as? [String] ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    var selectedGroup: ProjectGroup? {
        groups?.first { $0.project == selection }
    }

    /// Scans the chosen folders. It scans even when none is chosen: that scan ends at once and overtakes any
    /// older scan of a folder just removed from the list, whose results then never land.
    func refresh() async {
        let folders = folders
        guard let (scan, standings) = await scanRun.run({
            let scan = await ProjectArtifacts.scan(roots: folders, exclusions: ExclusionsStore.shared.exclusions)
            return (scan, await TimeMachineExclusion.standings(of: scan.artifacts.map(\.url)))
        }) else { return }
        let artifacts = scan.artifacts
        wasCutShort = scan.wasCutShort
        needsFullDiskAccess = scan.needsFullDiskAccess
        unreadable = scan.unreadableLocations
        let result = Dictionary(grouping: artifacts, by: \.project)
            .map {
                ProjectGroup(
                    project: $0.key,
                    artifacts: $0.value.sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) }
                )
            }
            .sorted { $0.total > $1.total }
        groups = result
        excludedFromBackups = Set(standings.filter { $0.value != .included }.keys)
        excludedFromAbove = Set(standings.filter { $0.value == .excludedFromAbove }.keys)
        selectedURLs.formIntersection(Set(artifacts.map(\.url)))
        if let selection, !result.contains(where: { $0.project == selection }) {
            self.selection = nil
        }
    }

    func addFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the folders your projects live in.")
        guard await panel.begin() == .OK else { return }
        await add(panel.urls)
    }

    /// The usual project folders in the home folder that are not on the list yet.
    var suggestedFolders: [URL] {
        ProjectArtifacts.suggestedRoots().filter { url in
            !folders.contains { $0.standardizedFileURL == url.standardizedFileURL }
        }
    }

    func add(_ urls: [URL]) async {
        let chosen = urls.filter { url in !folders.contains { $0.standardizedFileURL == url.standardizedFileURL } }
        // A folder that cannot be scanned is refused here, rather than saved and then silently skipped.
        refused = chosen.compactMap { url in ProjectArtifacts.refusal(for: url).map { (url, $0) } }
        let keeping = chosen.filter { url in !refused.contains { $0.url == url } }
        guard !keeping.isEmpty else { return }
        folders += keeping
        save()
        await refresh()
    }

    func clearRefusals() {
        refused = []
    }

    func removeFolder(_ url: URL) async {
        folders.removeAll { $0 == url }
        save()
        await refresh()
    }

    /// True when every artifact the checkbox acts on is excluded from backups. Artifacts with a generic name
    /// are never excluded by it, so they are not counted.
    func isExcludedFromBackups(_ group: ProjectGroup) -> Bool {
        let marked = group.artifacts.filter { !$0.hasGenericName }
        return !marked.isEmpty && marked.allSatisfy { excludedFromBackups.contains($0.url) }
    }

    /// The group's folders that would not take the mark the last time Peel set it.
    func backupMarkFailures(in group: ProjectGroup) -> [URL] {
        group.artifacts.map(\.url).filter(backupMarkFailures.contains)
    }

    /// False when no artifact of the group can take the mark, so the checkbox has nothing to change.
    func canMarkForBackups(_ group: ProjectGroup) -> Bool {
        !ProjectArtifacts.markableForBackups(group.artifacts, excludedFromAbove: excludedFromAbove).isEmpty
    }

    /// Excludes the group's artifacts from Time Machine backups, or includes them again, so a backup holds the
    /// project and not what a build can make again.
    func setExcludedFromBackups(_ isExcluded: Bool, in group: ProjectGroup) {
        let urls = ProjectArtifacts.markableForBackups(group.artifacts, excludedFromAbove: excludedFromAbove)
        let failed = TimeMachineExclusion.setExcluded(isExcluded, urls)
        backupMarkFailures = backupMarkFailures.subtracting(urls).union(failed)
        let changed = Set(urls).subtracting(failed)
        if isExcluded {
            excludedFromBackups.formUnion(changed)
        } else {
            excludedFromBackups.subtract(changed)
        }
    }

    private func save() {
        UserDefaults.standard.set(folders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
    }

    private func group(of page: CarriedSelection.Page) -> ProjectGroup? {
        groups?.first { $0.page == page }
    }
}

extension ProjectLibrary: CarriesSelection {
    var carriedParts: [CarriedSelection.Part] {
        (groups ?? []).compactMap { group in
            let selected = group.artifacts.filter { selectedURLs.contains($0.url) }
            guard !selected.isEmpty else { return nil }
            return CarriedSelection.Part(
                page: group.page,
                title: group.project.lastPathComponent,
                source: group.project.lastPathComponent,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let group = group(of: part.page) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let urls = group.artifacts.map(\.url).filter { selectedURLs.contains($0) && part.sizes.keys.contains($0) }
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(urls)
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh()
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = group(of: page)?.project
    }
}
