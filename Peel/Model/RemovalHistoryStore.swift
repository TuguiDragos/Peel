import Accessibility
import Foundation
import Observation
import PeelCore

nonisolated struct RemovalBatch: Identifiable, Hashable {
    let id: UUID
    /// Every tool the batch moved from, in the order they moved: one, or several for a batch that moved what was
    /// selected in more than one tool.
    let tools: [Tool]
    let date: Date
    let records: [RemovalRecord]
    /// The title the row shows: the parts' titles in the order they moved, or the first few and how many more
    /// pages there are.
    let title: String
    /// Every part's title, which a search looks through. A source Peel stored with a key is shown in the user's
    /// language, any other source as stored.
    let partTitles: [String]

    init(id: UUID, parts: [RemovalPart], date: Date, records: [RemovalRecord]) {
        self.id = id
        tools = Self.tools(of: parts)
        self.date = date
        self.records = records
        partTitles = Self.titles(of: parts)
        title = Self.title(naming: partTitles)
    }

    /// The one tool the batch moved from, or nil for a batch from several.
    var tool: Tool? { tools.count == 1 ? tools[0] : nil }

    static func tools(of parts: [RemovalPart]) -> [Tool] {
        var tools: [Tool] = []
        for tool in parts.compactMap({ Tool(rawValue: $0.tool) }) where !tools.contains(tool) {
            tools.append(tool)
        }
        return tools
    }

    static func titles(of parts: [RemovalPart]) -> [String] {
        parts.map { title(source: $0.source, key: $0.sourceKey, tool: Tool(rawValue: $0.tool)) }
    }

    static func title(naming titles: [String]) -> String {
        RemovalPart.name(titles, more: { String(inflecting: "^[\($0) more page](inflect: true)") }) {
            $0.formatted(.list(type: .and))
        }
    }

    static func title(source: String, key: String?, tool: Tool?) -> String {
        guard let key else { return source }
        if key == "tool", let tool { return String(localized: tool.title) }
        // What a removal moved before Peel quit or stopped, taken into History the next time it was read.
        if key == "interrupted" { return String(localized: "Interrupted Removal") }
        if key.hasPrefix("space."), let words = SpaceItem.words(for: String(key.dropFirst("space.".count))) {
            return String(localized: words.title)
        }
        if key.hasPrefix("installers."), let kind = InstallerItem.Kind(rawValue: String(key.dropFirst("installers.".count))) {
            return String(localized: kind.title)
        }
        if key.hasPrefix("apps."), let count = Int(key.dropFirst("apps.".count)) {
            return String(inflecting: "^[\(count) app](inflect: true)")
        }
        if key.hasPrefix("casks."), let count = Int(key.dropFirst("casks.".count)) {
            return String(inflecting: "^[\(count) cask](inflect: true)")
        }
        if key.hasPrefix("reset.") {
            return String(localized: "Reset of \(String(key.dropFirst("reset.".count)))")
        }
        if key.hasPrefix("savedSettings.") {
            return String(localized: "Settings Saved for \(String(key.dropFirst("savedSettings.".count)))")
        }
        return source
    }

    /// What Edit > Undo says for a removal of `parts` titled `title`: a reset is undone by name, anything else as a
    /// removal.
    static func undoTitle(of parts: [RemovalPart], title: String) -> String {
        if parts.count == 1, let key = parts[0].sourceKey, key.hasPrefix("reset.") {
            return String(localized: "Undo Reset \(String(key.dropFirst("reset.".count)))")
        }
        return String(localized: "Undo Remove \(title)")
    }

    var size: SizeTotal { records.totalSize }

    @MainActor
    var movedAnnouncement: AttributedString {
        size.isComplete && size.known > 0
            ? AttributedString(localized: "Moved ^[\(records.count) item](inflect: true) to the Trash, \(size.known.byteCount).")
            : AttributedString(localized: "Moved ^[\(records.count) item](inflect: true) to the Trash.")
    }
}

/// A removal written into History part by part, so what each part moved is there as soon as it moved, and told
/// once, by `RemovalHistoryStore.finish`.
struct RemovalInProgress {
    let batch = UUID()
    /// What the removal refused is an entry of its own, and History's list tells its entries apart by id, so it
    /// never shares the removal's.
    let refusals = UUID()
    fileprivate(set) var records: [RemovalRecord] = []
    /// True once History couldn't record a part of it, so Put Back has nothing to go on for what moved.
    fileprivate(set) var wasNotRecorded = false
}

/// What Peel was asked to move in one removal and did not.
nonisolated struct RefusalBatch: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let records: [RefusalRecord]
    /// The sources in the user's language, named as `RemovalBatch` names them.
    let title: String
    let partTitles: [String]

    init(_ group: RefusalGroup) {
        id = group.id
        date = group.date
        records = group.records
        partTitles = RemovalBatch.titles(of: group.parts)
        title = RemovalBatch.title(naming: partTitles)
    }
}

@Observable
final class RemovalHistoryStore {
    private let log: RemovalLog
    private let refusals: RefusalLog
    /// Where a removal History couldn't record is told, with whatever else the removal left to tell, and what an
    /// Undo left in the Trash.
    private let outcome: RemovalOutcome?
    private let knowsTheExclusions: () -> Bool
    private let restoring: ([TrashedItem], Bool) async -> [RestoreFailure?]
    /// Read again here once History has counted a removal, rather than by each tool.
    var stats: LifetimeStats?
    /// The last batch moved, for Undo. `@Environment(\.undoManager)` is nil in an app with no documents,
    /// so the Edit menu's own item is replaced by one that asks this (`PeelCommands`).
    private(set) var undoable: (records: [RemovalRecord], title: String)?
    /// The last batch moved in this session, which the removal bar briefly reports.
    private(set) var justMoved: RemovalBatch?
    /// Whether the helper can act. The window keeps this current, so Undo in the Edit menu can use the helper.
    var canUseHelper = false
    private(set) var records: [RemovalRecord] = []
    /// The records grouped into batches. Worked out once when the records change, because the list reads this
    /// several times per render.
    private(set) var batches: [RemovalBatch] = []
    /// Whether the log and the refusals have been read at all, so an empty list is not taken for an empty History.
    private(set) var hasLoaded = false
    /// What a search looks through, built once with the batches rather than walked on every keystroke.
    private(set) var searchKeys: [RemovalBatch.ID: String] = [:]
    /// What Peel was asked to move and did not, one removal to an entry, newest first.
    private(set) var refusalBatches: [RefusalBatch] = []
    private(set) var refusalSearchKeys: [RefusalBatch.ID: String] = [:]
    /// Moves only when the removals or refusals listed change, so a search over the earlier lists is made again.
    private(set) var revision = 0
    /// What the last read or change of the refusal log met, which the Not Moved list says.
    private(set) var refusalProblem: RefusalLogProblem?
    private(set) var problem: RemovalLogProblem?
    /// Whether History cannot be read, which holds every removal back, as the Trash service does. Known without
    /// reading it: at launch, when Peel comes forward, and with every read or change of History.
    private(set) var isUnreadable = false
    /// Whether History cannot be written, as on a full disk, which holds every removal back too. Known the same way.
    private(set) var cannotBeWritten = false
    private(set) var isRestoring = false
    var selection: RemovalBatch.ID?
    /// By record, not by path: Space and Developer move the same cache folders again and again, so one path
    /// sits in many batches.
    var selectedIDs: Set<RemovalRecord.ID> = []
    var failures: [RemovalRecord.ID: RestoreFailure] = [:]
    /// Counts the times History was read again, by Reload or as Peel came forward, so a removal's page then looks in
    /// the Trash again with the records as they are now.
    private(set) var rereads = 0
    /// Counts, for each tool, the Put Backs that brought back what it had moved, so its page lists them again.
    private(set) var putBack: [Tool: Int] = [:]
    /// The count each page last listed under, kept here so a page off screen at a Put Back lists it when it returns.
    @ObservationIgnored private var listedAfterPutBack = ScannedRevisions()
    @ObservationIgnored private var listedRefusals: [RefusalRecord] = []
    /// Counts each change of what History lists. The lists are prepared off the main actor, and one prepared for an
    /// older change must never replace a newer one.
    private var listedChange = 0
    private var refusalChange = 0

    var selectedBatch: RemovalBatch? {
        batches.first { $0.id == selection }
    }

    var selectedRefusals: RefusalBatch? {
        refusalBatches.first { $0.id == selection }
    }

    /// `restoring` puts items back, for each the reason it stayed or nil, and `knowsTheExclusions` says whether
    /// anything may move: both are the app's own unless a test stands in for them.
    init(
        log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog(),
        outcome: RemovalOutcome? = nil,
        knowsTheExclusions: @escaping () -> Bool = { ExclusionsStore.shared.exclusions.isKnown },
        restoring: @escaping ([TrashedItem], Bool) async -> [RestoreFailure?] = { items, canUseHelper in
            await TrashService(exclusions: ExclusionsStore.shared.exclusions).restore(items, canUseHelper: canUseHelper)
        }
    ) {
        self.log = log
        self.refusals = refusals
        self.outcome = outcome
        self.knowsTheExclusions = knowsTheExclusions
        self.restoring = restoring
    }

    func load() async {
        await apply(await log.load())
        await loadRefusals()
        hasLoaded = true
    }

    /// Shows History as a page opened anew would: read again, without the reasons the last Put Back gave, and with
    /// the Trash looked at again.
    func reload() async {
        failures = [:]
        await readAgain()
    }

    /// Reads History again as Peel comes forward, since `peel` may have moved or put back something meanwhile, once
    /// History is in use: its page was opened, or Undo can put back a removal of this session.
    func readAgainIfInUse() async {
        guard hasLoaded || undoable != nil else { return }
        await readAgain()
    }

    /// Reads History before a removal's page looks in the Trash, so the page never looks with records `peel` changed.
    private func readAgain() async {
        await load()
        rereads += 1
    }

    /// The problem History's page shows: that History cannot be read, as soon as that is known, otherwise what the
    /// last read or change of it met.
    var shownProblem: RemovalLogProblem? {
        isUnreadable ? .unreadable : problem
    }

    /// Looks again at whether History can be read and written, which costs no read of it.
    func checkReadability() {
        let unreadable = !RemovalLog.canBeRead(at: log.url)
        let unwritable = !unreadable && !RemovalLog.canBeWritten(at: log.url)
        if isUnreadable != unreadable { isUnreadable = unreadable }
        if cannotBeWritten != unwritable { cannotBeWritten = unwritable }
    }

    /// Keeps a History that cannot be read beside a new one, and records again.
    func startOver() async {
        await apply(await log.startOver())
    }

    private func loadRefusals() async {
        let read = await refusals.load()
        refusalProblem = read.problem
        refusalChange += 1
        let change = refusalChange
        let records = read.records ?? []
        // The refusals listed already, read again, change nothing; an older listing still on its way is dropped.
        guard records != listedRefusals else { return }
        let listed = await Self.listed(records)
        guard change == refusalChange else { return }
        listedRefusals = records
        refusalBatches = listed.batches
        refusalSearchKeys = listed.searchKeys
        revision += 1
    }

    /// Records a removal from one place in History, as one entry. When Peel wrote the source itself, pass it in
    /// English along with a `sourceKey`, so History can show it in the user's language (see
    /// `RemovalRecord.sourceKey`). An item missing from `sizes` is recorded as unknown.
    func record(
        _ result: TrashResult,
        tool: Tool,
        source: String,
        sourceKey: String? = nil,
        sizes: [URL: Int64],
        sharingStorage: Set<URL> = []
    ) async {
        var removal = RemovalInProgress()
        await record(
            result,
            part: RemovalPart(source: source, sourceKey: sourceKey, tool: tool.rawValue),
            sizes: sizes,
            sharingStorage: sharingStorage,
            in: &removal
        )
        finish(removal)
    }

    /// Records in History what one part of `removal` moved, and what it refused.
    func record(
        _ result: TrashResult,
        part: RemovalPart,
        sizes: [URL: Int64],
        sharingStorage: Set<URL> = [],
        in removal: inout RemovalInProgress
    ) async {
        // History first: it is the way back for what just moved, and nothing that follows may keep it unwritten.
        if !result.trashed.isEmpty {
            let new = part.records(of: result, sizes: sizes, sharingStorage: sharingStorage, batch: removal.batch)
            removal.records += new
            let added = await log.add(new)
            if added.records == nil { removal.wasNotRecorded = true }
            await apply(added)
        }
        // Refusals are logged whether or not anything moved: a removal where nothing moved is the one most worth a
        // record.
        let refusalProblem = await refusals.add(
            result.failures, source: part.source, sourceKey: part.sourceKey, tool: part.tool, batch: removal.refusals
        )
        if !result.failures.isEmpty {
            await loadRefusals()
        }
        if let refusalProblem {
            self.refusalProblem = refusalProblem
        }
        checkReadability()
    }

    /// Tells what `removal` moved once every part of it is recorded: the bar's "Moved", VoiceOver, the lifetime
    /// totals, and Undo.
    func finish(_ removal: RemovalInProgress) {
        guard !removal.records.isEmpty else { return }
        if removal.wasNotRecorded { outcome?.noteHistoryCouldNotRecord() }
        let parts = RemovalPart.of(removal.records.map { ($0.date, $0.part) })
        let moved = RemovalBatch(id: removal.batch, parts: parts, date: .now, records: removal.records)
        justMoved = moved
        AccessibilityNotification.Announcement(moved.movedAnnouncement).post()
        stats?.reload()
        registerUndo(of: removal.records, title: RemovalBatch.undoTitle(of: parts, title: moved.title))
    }

    /// Makes the last batch undoable, as Finder does after a move to the Trash: Command-Z puts it back, and the
    /// Edit menu names it. Put Back in History does the same, and both refuse an item that has since left the Trash.
    private func registerUndo(of records: [RemovalRecord], title: String) {
        undoable = records.isEmpty ? nil : (records, title)
    }

    /// What the Edit menu shows, and nil when there is nothing to undo.
    var undoTitle: String? { undoable?.title }

    /// Why nothing may move to the Trash or back now: the exclusions are not known, or History can't be read or
    /// written.
    var holdingReason: TrashFailure.Reason? {
        guard knowsTheExclusions() else { return .guarded(.exclusionsNotKnown) }
        if isUnreadable { return .historyUnreadable }
        return cannotBeWritten ? .historyCannotBeWritten : nil
    }

    var mayMove: Bool { holdingReason == nil }

    /// Puts the last batch back. Nothing happens while another Put Back runs or none may, and the batch stays
    /// undoable: `restore` takes one at a time and would drop this one without a word.
    func undoLastRemoval() async {
        guard let undoable, !isRestoring, mayMove else { return }
        self.undoable = nil
        let stayed = await restore(undoable.records, canUseHelper: canUseHelper, tellingThePage: false)
        guard !stayed.isEmpty else { return }
        outcome?.reportPutBack(stayed.map {
            RemovalOutcome.PutBackFailure(url: $0.record.originalURL, failure: $0.failure)
        })
        // What stayed for a reason that can pass, such as the helper or something in its place, can be asked again.
        let again = stayed.filter { !$0.failure.isFinal }.map(\.record)
        if !again.isEmpty { self.undoable = (again, undoable.title) }
    }

    /// Whether a Put Back brought back what `tool` moved since its page last asked. False the first time it asks.
    func needsRescanAfterPutBack(_ tool: Tool) -> Bool {
        listedAfterPutBack.needsRescan(tool.rawValue, at: putBack[tool, default: 0])
    }

    /// Takes the records `ids` names out of what Undo would put back, once they are back or gone from History.
    private func keepUndoable(without ids: Set<RemovalRecord.ID>) {
        guard let undoable, !ids.isEmpty else { return }
        let left = undoable.records.filter { !ids.contains($0.id) }
        guard left.count != undoable.records.count else { return }
        self.undoable = left.isEmpty ? nil : (left, undoable.title)
    }

    /// Shows the log's records, or keeps what is already on screen when the log was left untouched or holds the
    /// records listed already.
    private func apply(_ outcome: RemovalLogOutcome) async {
        problem = outcome.problem
        checkReadability()
        guard let records = outcome.records else { return }
        // What left History since it was listed, as by `peel restore`, is no longer Undo's to put back.
        keepUndoable(without: Set(self.records.map(\.id)).subtracting(records.map(\.id)))
        listedChange += 1
        let change = listedChange
        guard let listed = await Self.listed(records, unless: self.records), change == listedChange else { return }
        self.records = records
        batches = listed.batches
        searchKeys = listed.searchKeys
        revision += 1
    }

    /// History's batches, newest first, and what a search looks through, or nil when `records` are those listed
    /// already. Worked out off the main actor, since History keeps up to `RemovalLog.maximumRecords` records.
    @concurrent
    private static func listed(
        _ records: [RemovalRecord], unless shown: [RemovalRecord]
    ) async -> (batches: [RemovalBatch], searchKeys: [RemovalBatch.ID: String])? {
        guard records != shown else { return nil }
        let batches = RemovalRecord.grouped(records).map { group in
            RemovalBatch(id: group.id, parts: group.parts, date: group.date, records: group.records)
        }
        let searchKeys = Dictionary(uniqueKeysWithValues: batches.map {
            ($0.id, searchKey(titles: $0.partTitles, names: $0.records.map(\.originalURL.lastPathComponent)))
        })
        return (batches, searchKeys)
    }

    /// What was refused, one removal to an entry, and what a search looks through, worked out off the main actor.
    @concurrent
    private static func listed(
        _ records: [RefusalRecord]
    ) async -> (batches: [RefusalBatch], searchKeys: [RefusalBatch.ID: String]) {
        let batches = RefusalRecord.grouped(records).map(RefusalBatch.init)
        let searchKeys = Dictionary(uniqueKeysWithValues: batches.map {
            ($0.id, searchKey(titles: $0.partTitles, names: $0.records.map(\.url.lastPathComponent)))
        })
        return (batches, searchKeys)
    }

    /// Puts `records` back and answers what stayed, each with why. History's page shows the reasons
    /// (`tellingThePage`); an Undo, asked from any page, has them told by the app instead.
    @discardableResult
    func restore(
        _ records: [RemovalRecord], canUseHelper: Bool, tellingThePage: Bool = true
    ) async -> [(record: RemovalRecord, failure: RestoreFailure)] {
        // One restore at a time, however often it is asked for: two rounds over the same records would each
        // report the items the other put back as already there.
        guard !isRestoring, mayMove else { return [] }
        isRestoring = true
        defer { isRestoring = false }
        return await QuitGuard.shared.run {
            var restored: Set<UUID> = []
            var problems: [RemovalRecord.ID: RestoreFailure] = [:]
            var stayed: [(record: RemovalRecord, failure: RestoreFailure)] = []
            let ordered = records.inPutBackOrder
            let disks = MountedDisks.now()
            let answers = await restoring(ordered.map { $0.located(on: disks).trashedItem }, canUseHelper)
            for (record, answer) in zip(ordered, answers) {
                if let failure = answer {
                    problems[record.id] = failure
                    stayed.append((record, failure))
                } else {
                    restored.insert(record.id)
                }
            }
            if tellingThePage { failures = problems }
            selectedIDs.subtract(restored)
            if !restored.isEmpty {
                keepUndoable(without: restored)
                for tool in Set(ordered.filter { restored.contains($0.id) }.compactMap { Tool(rawValue: $0.tool) }) {
                    putBack[tool, default: 0] += 1
                }
                await apply(await log.remove(restored))
                // A move is announced, and so is its undoing: the rows only vanish from the list.
                AccessibilityNotification.Announcement(
                    AttributedString(localized: "Put back ^[\(restored.count) item](inflect: true).")
                ).post()
            }
            return stayed
        }
    }

    /// Removes `records` from History. The page offers this for items that have left the Trash.
    func forget(_ records: [RemovalRecord]) async {
        keepUndoable(without: Set(records.map(\.id)))
        await apply(await log.remove(Set(records.map(\.id))))
        selectedIDs.subtract(records.map(\.id))
    }

    func isSelected(_ record: RemovalRecord) -> Bool {
        selectedIDs.contains(record.id)
    }

    func setSelected(_ isSelected: Bool, _ record: RemovalRecord) {
        if isSelected {
            selectedIDs.insert(record.id)
        } else {
            selectedIDs.remove(record.id)
        }
    }


    /// A batch's part titles and the name of each item in it, joined into one string, so a search makes one call
    /// per batch rather than one per record.
    nonisolated private static func searchKey(titles: [String], names: [String]) -> String {
        (titles + names).joined(separator: "\n")
    }

}
