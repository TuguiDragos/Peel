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
    /// The title the row shows: each part's source, in the order they moved. A source Peel stored with a key is
    /// shown in the user's language, any other source as stored.
    let title: String

    init(id: UUID, parts: [RemovalPart], date: Date, records: [RemovalRecord]) {
        self.id = id
        tools = Self.tools(of: parts)
        self.date = date
        self.records = records
        title = Self.title(of: parts)
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

    static func title(of parts: [RemovalPart]) -> String {
        parts.map { title(source: $0.source, key: $0.sourceKey, tool: Tool(rawValue: $0.tool)) }
            .formatted(.list(type: .and))
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
        return source
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
}

/// What Peel was asked to move in one removal and did not.
nonisolated struct RefusalBatch: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let records: [RefusalRecord]
    /// The sources in the user's language, as `RemovalBatch.title(of:)` gives them.
    let title: String

    init(_ group: RefusalGroup) {
        id = group.id
        date = group.date
        records = group.records
        title = RemovalBatch.title(of: group.parts)
    }
}

@Observable
final class RemovalHistoryStore {
    private let log = RemovalLog()
    private let refusals = RefusalLog()
    /// Read again here once History has counted a removal, rather than by each tool.
    var stats: LifetimeStats?
    /// The last batch moved, for Undo. `@Environment(\.undoManager)` is nil in an app with no documents,
    /// so the Edit menu's own item is replaced by one that asks this (`PeelCommands`).
    private(set) var undoable: (records: [RemovalRecord], source: String)?
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
    private(set) var isRestoring = false
    var selection: RemovalBatch.ID?
    /// By record, not by path: Space and Developer move the same cache folders again and again, so one path
    /// sits in many batches.
    var selectedIDs: Set<RemovalRecord.ID> = []
    var failures: [RemovalRecord.ID: RestoreFailure] = [:]
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

    func load() async {
        await apply(await log.load())
        await loadRefusals()
        hasLoaded = true
    }

    /// The problem History's page shows: that History cannot be read, as soon as that is known, otherwise what the
    /// last read or change of it met.
    var shownProblem: RemovalLogProblem? {
        isUnreadable ? .unreadable : problem
    }

    /// Looks again at whether History can be read, which costs no read of it.
    func checkReadability() {
        isUnreadable = !RemovalLog.canBeRead(at: log.url)
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
        let listed = await Self.listed(read.records ?? [])
        guard change == refusalChange else { return }
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
        sizes: [URL: Int64]
    ) async {
        var removal = RemovalInProgress()
        await record(
            result,
            part: RemovalPart(source: source, sourceKey: sourceKey, tool: tool.rawValue),
            sizes: sizes,
            in: &removal
        )
        finish(removal)
    }

    /// Records in History what one part of `removal` moved, and what it refused.
    func record(
        _ result: TrashResult,
        part: RemovalPart,
        sizes: [URL: Int64],
        in removal: inout RemovalInProgress
    ) async {
        // History first: it is the way back for what just moved, and nothing that follows may keep it unwritten.
        if !result.trashed.isEmpty {
            let new = part.records(of: result, sizes: sizes, batch: removal.batch)
            removal.records += new
            await apply(await log.add(new))
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
        let moved = RemovalBatch(
            id: removal.batch,
            parts: RemovalPart.of(removal.records.map { ($0.date, $0.part) }),
            date: .now,
            records: removal.records
        )
        justMoved = moved
        AccessibilityNotification.Announcement(moved.movedAnnouncement).post()
        stats?.reload()
        registerUndo(of: removal.records, source: moved.title)
    }

    /// Makes the last batch undoable, as Finder does after a move to the Trash: Command-Z puts it back, and the
    /// Edit menu names its source. Put Back in History does the same, and both refuse an item that has since
    /// left the Trash.
    private func registerUndo(of records: [RemovalRecord], source: String) {
        undoable = records.isEmpty ? nil : (records, source)
    }

    /// The name the Edit menu shows, and nil when there is nothing to undo.
    var undoName: String? { undoable?.source }

    /// Puts the last batch back. Nothing happens while another Put Back runs, and the batch stays undoable: `restore`
    /// takes one at a time and would drop this one without a word.
    func undoLastRemoval() async {
        guard let undoable, !isRestoring else { return }
        self.undoable = nil
        await restore(undoable.records, canUseHelper: canUseHelper)
    }

    /// Shows the log's records, or keeps what is already on screen when the log was left untouched or holds the
    /// records listed already.
    private func apply(_ outcome: RemovalLogOutcome) async {
        problem = outcome.problem
        checkReadability()
        guard let records = outcome.records else { return }
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
            ($0.id, searchKey(title: $0.title, names: $0.records.map(\.originalURL.lastPathComponent)))
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
            ($0.id, searchKey(title: $0.title, names: $0.records.map(\.url.lastPathComponent)))
        })
        return (batches, searchKeys)
    }

    func restore(_ records: [RemovalRecord], canUseHelper: Bool) async {
        // One restore at a time, however often it is asked for: two rounds over the same records would each
        // report the items the other put back as already there.
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let service = TrashService()
        await QuitGuard.shared.run {
            var restored: Set<UUID> = []
            var problems: [RemovalRecord.ID: RestoreFailure] = [:]
            for record in records.inPutBackOrder {
                if let failure = await service.restore(record.trashedItem, canUseHelper: canUseHelper) {
                    problems[record.id] = failure
                } else {
                    restored.insert(record.id)
                }
            }
            failures = problems
            selectedIDs.subtract(restored)
            if !restored.isEmpty {
                await apply(await log.remove(restored))
                // A move is announced, and so is its undoing: the rows only vanish from the list.
                AccessibilityNotification.Announcement(
                    AttributedString(localized: "Put back ^[\(restored.count) item](inflect: true).")
                ).post()
            }
        }
    }

    /// Removes `records` from History. The page offers this for items that have left the Trash.
    func forget(_ records: [RemovalRecord]) async {
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


    /// A batch's title and the name of each item in it, joined into one string, so a search makes one call
    /// per batch rather than one per record.
    nonisolated private static func searchKey(title: String, names: [String]) -> String {
        ([title] + names).joined(separator: "\n")
    }

}
