import AppKit
import Foundation
import Observation
import PeelCore

/// One project folder and everything a build left inside it.
struct ProjectGroup: Identifiable, Hashable {
    let project: URL
    /// The folder's name, with the folders above it while another listed project has a folder of the same name.
    let name: String
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
    /// The chosen folders the last scan didn't search at all, each with the reason.
    private(set) var unsearchable: [(url: URL, reason: ProjectArtifacts.Refusal)] = []
    /// Folders the last Add refused, with the reason, until the next one.
    private(set) var refused: [(url: URL, reason: ProjectArtifacts.Refusal)] = []
    /// The usual project folders that are in the home folder, read off the main actor (`readSuggestions()`).
    private var suggestedRoots: [URL] = []
    var selection: URL?
    var selectedURLs: Set<URL> = []

    private let defaults: UserDefaults
    @ObservationIgnored private var scannedAt: ContinuousClock.Instant?

    /// How long what a scan saw is shown before the page, appearing or with Peel coming forward, looks again.
    static let scanAgainAfter: Duration = .seconds(60 * 60)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        folders = (defaults.array(forKey: Self.foldersKey) as? [String] ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        Task { await readSuggestions() }
    }

    /// Reads which of the usual project folders are in the home folder, so the page offers them without reading
    /// the disk while it draws.
    func readSuggestions() async {
        suggestedRoots = await ProjectArtifacts.suggestedRoots()
    }

    /// Scans unless the last scan ended less than `age` ago, one or a removal runs, or the last scan was stopped: a
    /// project changed in the last 7 days is held back, so what a scan saw ages.
    func refreshUnlessScanned(within age: Duration) async {
        guard !scanRun.isWaitedFor, !isRemoving, !scanRun.wasStopped else { return }
        if let scannedAt, ContinuousClock.now - scannedAt < age { return }
        await refresh()
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
        scannedAt = .now
        let artifacts = scan.artifacts
        wasCutShort = scan.wasCutShort
        needsFullDiskAccess = scan.needsFullDiskAccess
        unreadable = scan.unreadableLocations
        unsearchable = scan.refusedRoots
        let byProject = Array(Dictionary(grouping: artifacts, by: \.project))
        let result = zip(byProject, ProjectArtifacts.names(of: byProject.map(\.key)))
            .map { entry, name in
                ProjectGroup(
                    project: entry.key,
                    name: name,
                    artifacts: entry.value.sorted { SizeTotal([$0.size]) > SizeTotal([$1.size]) }
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
        suggestedRoots.filter { !isListed($0) }
    }

    func add(_ urls: [URL]) async {
        let chosen = urls.filter { !isListed($0) }
        let reasons = await ProjectArtifacts.refusals(of: chosen)
        // A folder that cannot be scanned is refused here, rather than saved and then silently skipped.
        refused = zip(chosen, reasons).compactMap { url, reason in reason.map { (url, $0) } }
        // Another Add may have listed one of them while these were judged.
        let keeping = zip(chosen, reasons).filter { url, reason in reason == nil && !isListed(url) }.map(\.0)
        guard !keeping.isEmpty else { return }
        folders += keeping
        save()
        await refresh()
    }

    private func isListed(_ url: URL) -> Bool {
        folders.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    func clearRefusals() {
        refused = []
    }

    func removeFolder(_ url: URL) async {
        folders.removeAll { $0 == url }
        save()
        await refresh()
    }

    private func backupMarks(_ group: ProjectGroup) -> ProjectArtifacts.BackupMarks {
        ProjectArtifacts.BackupMarks(
            group.artifacts, excluded: excludedFromBackups, excludedFromAbove: excludedFromAbove
        )
    }

    func isExcludedFromBackups(_ group: ProjectGroup) -> Bool {
        backupMarks(group).isOn
    }

    /// The group's folders that would not take the mark the last time Peel set it.
    func backupMarkFailures(in group: ProjectGroup) -> [URL] {
        group.artifacts.map(\.url).filter(backupMarkFailures.contains)
    }

    func canMarkForBackups(_ group: ProjectGroup) -> Bool {
        backupMarks(group).canChange
    }

    func markedByOthers(in group: ProjectGroup) -> [URL] {
        backupMarks(group).markedByOthers
    }

    /// Excludes the group's artifacts from Time Machine backups, or includes them again, so a backup holds the
    /// project and not what a build can make again.
    func setExcludedFromBackups(_ isExcluded: Bool, in group: ProjectGroup) {
        let urls = backupMarks(group).folders(turning: isExcluded)
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
        defaults.set(folders.map { $0.path(percentEncoded: false) }, forKey: Self.foldersKey)
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
                title: group.name,
                source: group.name,
                sourceKey: nil,
                sizes: Dictionary(selected.map { ($0.url, $0.size) }, uniquingKeysWith: { first, _ in first })
            )
        }
    }

    func move(_ part: CarriedSelection.Part, apps: AppLibrary) async -> TrashResult? {
        guard let group = group(of: part.page) else { return TrashResult() }
        isRemoving = true
        defer { isRemoving = false }
        let chosen = group.artifacts.filter { selectedURLs.contains($0.url) && part.sizes.keys.contains($0.url) }
        let changed = await ProjectArtifacts.changedSinceScan(chosen, among: (groups ?? []).flatMap(\.artifacts))
        return await TrashService(exclusions: ExclusionsStore.shared.exclusions).trash(
            chosen.map(\.url),
            refusing: { changed.contains($0) ? .changedSinceScan : nil }
        )
    }

    func refresh(after parts: [CarriedSelection.Part], apps: AppLibrary) async {
        await refresh()
    }

    func choose(_ page: CarriedSelection.Page) {
        selection = group(of: page)?.project
    }
}
