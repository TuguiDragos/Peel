import Accessibility
import Foundation
import Observation
import PeelCore

struct RemovalBatch: Identifiable, Hashable {
    let id: UUID
    let source: String
    let sourceKey: String?
    let tool: Tool?
    let date: Date
    let records: [RemovalRecord]
    /// The title the row shows. A source Peel stored with a key is shown in the user's language, any other
    /// source as stored.
    let title: String

    init(id: UUID, source: String, sourceKey: String?, tool: Tool?, date: Date, records: [RemovalRecord]) {
        self.id = id
        self.source = source
        self.sourceKey = sourceKey
        self.tool = tool
        self.date = date
        self.records = records
        title = Self.title(source: source, key: sourceKey, tool: tool)
    }

    static func title(source: String, key: String?, tool: Tool?) -> String {
        guard let key else { return source }
        if key == "tool", let tool { return String(localized: tool.title) }
        if key.hasPrefix("space."), let words = SpaceItem.words(for: String(key.dropFirst("space.".count))) {
            return String(localized: words.title)
        }
        if key.hasPrefix("installers."), let kind = InstallerItem.Kind(rawValue: String(key.dropFirst("installers.".count))) {
            return String(localized: kind.title)
        }
        if key.hasPrefix("apps."), let count = Int(key.dropFirst("apps.".count)) {
            return String(inflecting: "^[\(count) app](inflect: true)")
        }
        return source
    }

    var size: SizeTotal { records.totalSize }

    var movedAnnouncement: AttributedString {
        size.isComplete && size.known > 0
            ? AttributedString(localized: "Moved ^[\(records.count) item](inflect: true) to the Trash, \(size.known.byteCount).")
            : AttributedString(localized: "Moved ^[\(records.count) item](inflect: true) to the Trash.")
    }
}

@Observable
final class RemovalHistoryStore {
    private let log = RemovalLog()
    private let refusals = RefusalLog()
    /// Updated here rather than by each tool, so no place that records a removal can forget to count it.
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
    /// Whether the log has been read at all, so an empty list is not taken for an empty History.
    private(set) var hasLoaded = false
    /// What a search looks through, built once with the batches rather than walked on every keystroke.
    private(set) var searchKeys: [RemovalBatch.ID: String] = [:]
    private(set) var problem: RemovalLogProblem?
    private(set) var isRestoring = false
    var selection: RemovalBatch.ID?
    /// By record, not by path: Space and Developer move the same cache folders again and again, so one path
    /// sits in many batches.
    var selectedIDs: Set<RemovalRecord.ID> = []
    var failures: [RemovalRecord.ID: RestoreFailure] = [:]

    /// Groups `records` into batches. The rule lives in `RemovalRecord.grouped`, where it is tested.
    private static func batches(of records: [RemovalRecord]) -> [RemovalBatch] {
        RemovalRecord.grouped(records).map { group in
            RemovalBatch(
                id: group.id,
                source: group.source,
                sourceKey: group.sourceKey,
                tool: Tool(rawValue: group.tool),
                date: group.date,
                records: group.records
            )
        }
    }

    var selectedBatch: RemovalBatch? {
        batches.first { $0.id == selection }
    }

    func load() async {
        apply(await log.load())
    }

    /// Records a removal in History. When Peel wrote the source itself, pass it in English along with a
    /// `sourceKey`, so History can show it in the user's language (see `RemovalRecord.sourceKey`). An item missing
    /// from `sizes` is recorded as unknown.
    func record(_ result: TrashResult, tool: Tool, source: String, sourceKey: String? = nil, sizes: [URL: Int64]) async {
        // Refusals are logged before the early return below: a removal where nothing moved is the one most
        // worth a record.
        await refusals.add(result.failures, source: source, tool: tool.rawValue)
        guard !result.trashed.isEmpty else { return }
        let batch = UUID()
        let new = result.trashed.map {
            RemovalRecord(batch: batch, item: $0, size: sizes[$0.originalURL], source: source, sourceKey: sourceKey, tool: tool.rawValue)
        }
        let moved = RemovalBatch(id: batch, source: source, sourceKey: sourceKey, tool: tool, date: .now, records: new)
        justMoved = moved
        AccessibilityNotification.Announcement(moved.movedAnnouncement).post()
        // History first: it is the way back for what just moved, and nothing that follows may keep it unwritten.
        apply(await log.add(new))
        stats?.add(result, sizes: sizes)
        registerUndo(of: new, source: moved.title)
    }

    /// Makes the last batch undoable, as Finder does after a move to the Trash: Command-Z puts it back, and the
    /// Edit menu names its source. Put Back in History does the same, and both refuse an item that has since
    /// left the Trash.
    private func registerUndo(of records: [RemovalRecord], source: String) {
        undoable = records.isEmpty ? nil : (records, source)
    }

    /// The name the Edit menu shows, and nil when there is nothing to undo.
    var undoName: String? { undoable?.source }

    func undoLastRemoval() async {
        guard let undoable else { return }
        self.undoable = nil
        await restore(undoable.records, canUseHelper: canUseHelper)
    }

    /// Shows the log's records, or keeps what is already on screen when the log was left untouched.
    private func apply(_ outcome: RemovalLogOutcome) {
        if let records = outcome.records {
            self.records = records
            batches = Self.batches(of: records)
            searchKeys = Dictionary(uniqueKeysWithValues: batches.map { ($0.id, Self.searchKey(of: $0)) })
        }
        problem = outcome.problem
        hasLoaded = true
    }

    func restore(_ records: [RemovalRecord], canUseHelper: Bool) async {
        // One restore at a time, however often it is asked for: two rounds over the same records would each
        // report the items the other put back as already there.
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        let service = TrashService()
        var restored: Set<UUID> = []
        var problems: [RemovalRecord.ID: RestoreFailure] = [:]
        // Shallowest first, so a folder is put back before anything that was inside it. A child put back first
        // would make a new folder at its parent's path, and the parent could then not be put back.
        for record in records.sorted(by: { $0.originalURL.pathComponents.count < $1.originalURL.pathComponents.count }) {
            if let failure = await service.restore(record.trashedItem, canUseHelper: canUseHelper) {
                problems[record.id] = failure
            } else {
                restored.insert(record.id)
            }
        }
        failures = problems
        selectedIDs.subtract(restored)
        if !restored.isEmpty {
            apply(await log.remove(restored))
        }
    }

    /// Removes `records` from History. The page offers this for items that have left the Trash.
    func forget(_ records: [RemovalRecord]) async {
        apply(await log.remove(Set(records.map(\.id))))
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


    /// The batch's title and the name of each item in it, joined into one string, so a search makes one call
    /// per batch rather than one per record.
    private static func searchKey(of batch: RemovalBatch) -> String {
        ([batch.title] + batch.records.map { $0.originalURL.lastPathComponent }).joined(separator: "\n")
    }

}
