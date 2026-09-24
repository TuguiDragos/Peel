import ArgumentParser
import Foundation
import PeelCore

/// One removal, as History shows it: everything that went in one go.
struct Batch {
    let id: UUID
    let records: [RemovalRecord]

    var date: Date { records.map(\.date).max() ?? .distantPast }
    var source: String { records.first?.source ?? "" }
    var tool: String { records.first?.tool ?? "" }
    var size: Int64 { records.totalSize }
    /// The records whose items are still in the Trash. An item emptied from the Trash can't be put back.
    var restorable: [RemovalRecord] { records.filter(\.isStillInTrash) }

    static func all(in records: [RemovalRecord]) -> [Batch] {
        Dictionary(grouping: records, by: \.batch)
            .map { Batch(id: $0.key, records: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.date > $1.date }
    }

    /// The first eight characters of the batch ID, which `peel history` shows and `peel restore` accepts.
    var shortID: String { String(id.uuidString.prefix(8)).lowercased() }

    func state(among records: [RemovalRecord]) -> String {
        if records.allSatisfy(\.isStillInTrash) { return "in the Trash" }
        if records.contains(where: { !$0.isOnAConnectedDisk }) { return "on a disk that isn't connected" }
        return restorable.isEmpty ? "gone from the Trash" : "partly gone from the Trash"
    }
}

struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List what Peel moved to the Trash.",
        discussion: "The same History the Peel app shows, written by both. Put a removal back with `peel restore`. With --refused, lists what Peel was asked to move and wouldn't, which nothing else keeps."
    )

    @Option(help: "Show at most this many removals.")
    var limit: Int = 20

    @Flag(help: "List what stayed and why, instead of what moved.")
    var refused = false

    @Flag(help: "Forget every refusal on record. Only with --refused.")
    var clear = false

    @OptionGroup var output: OutputOptions

    private struct Record: Encodable {
        let batch: String
        let date: Date
        let source: String
        let tool: String
        let size: Int64
        let itemCount: Int
        let restorableCount: Int
        let files: [FileRecord]
    }

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit has to be at least 1.") }
        guard !clear || refused else { throw ValidationError("--clear only goes with --refused. What moved is forgotten from History in the Peel app.") }
    }

    func run() async throws {
        try await run(in: RemovalLog(), refusals: RefusalLog())
    }

    func run(in log: RemovalLog, refusals: RefusalLog) async throws {
        guard !refused else { return try await listRefusals(in: refusals) }
        let outcome = await log.load()
        guard let records = outcome.records else {
            throw CommandFailure("Peel couldn't read its History.\(outcome.problem.map { " \($0.summary)" } ?? "")")
        }
        let batches = Array(Batch.all(in: records).prefix(limit))

        if output.json {
            try Output.json(batches.map { batch in
                Record(
                    batch: batch.id.uuidString,
                    date: batch.date,
                    source: batch.source,
                    tool: batch.tool,
                    size: batch.size,
                    itemCount: batch.records.count,
                    restorableCount: batch.restorable.count,
                    files: batch.records.map { FileRecord(path: Output.path($0.originalURL), size: MeasuredSize($0.size)) }
                )
            })
        } else if batches.isEmpty {
            Output.line("Peel hasn't moved anything to the Trash yet.")
        } else {
            Output.table(Self.rows(for: batches))
        }
        if let problem = outcome.problem {
            Output.note(problem.summary)
        }
    }

    static func rows(for batches: [Batch]) -> [[String]] {
        [["ID", "WHEN", "WHAT", "ITEMS", "SIZE", "STATE"]] + batches.map { batch in
            [
                batch.shortID,
                Output.day(batch.date),
                batch.source,
                Output.number(batch.records.count),
                Output.size(batch.size),
                batch.state(among: batch.records),
            ]
        }
    }

    static func rows(for records: [RefusalRecord]) -> [[String]] {
        [["WHEN", "WHAT", "WHY", "PATH"]] + records.map { record in
            [Output.day(record.date), record.source, record.detail ?? record.reason, Output.path(record.url)]
        }
    }

    private func listRefusals(in log: RefusalLog) async throws {
        guard !clear else {
            guard await log.clear() else { throw CommandFailure("Peel couldn't forget its refusals.") }
            Output.line("Forgot every refusal on record.")
            return
        }
        let records = Array(await log.load().sorted { $0.date > $1.date }.prefix(limit))

        if output.json {
            try Output.json(records)
        } else if records.isEmpty {
            Output.line("Peel hasn't refused anything it was asked to move.")
        } else {
            Output.table(Self.rows(for: records))
        }
    }
}

struct RestoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Put a removal back where it came from.",
        discussion: """
            ID is what `peel history` shows in its first column; the first few characters are enough.
            Items that need administrator access are left for the Peel app. Answering no exits with code 2; a \
            restore that couldn't finish exits 1.
            """
    )

    @Argument(help: "The removal to put back.")
    var id: String

    @Flag(help: "Show what would go back without moving anything.")
    var dryRun = false

    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.")
    var yes = false

    func validate() throws {
        guard !id.isEmpty else { throw ValidationError("Give the ID of a removal. See `peel history`.") }
        if !yes, !dryRun {
            try Output.requireConfirmable()
        }
    }

    /// Returns the one batch whose ID starts with `id`, ignoring case. A prefix that fits two batches is refused
    /// rather than guessed at.
    static func batch(matching id: String, in batches: [Batch]) throws -> Batch {
        let wanted = id.lowercased()
        let found = batches.filter { $0.id.uuidString.lowercased().hasPrefix(wanted) }
        guard !found.isEmpty else {
            throw CommandFailure("No removal starts with \(Output.quoted(id)). See `peel history`.")
        }
        guard found.count == 1 else {
            throw CommandFailure("\(Output.count(found.count, "removal starts", "removals start")) with \(Output.quoted(id)): \(found.map(\.shortID).joined(separator: ", ")).")
        }
        return found[0]
    }

    func run() async throws {
        try await run(in: RemovalLog(), using: TrashService(exclusions: await ExclusionStore().load()))
    }

    func run(in log: RemovalLog, using service: TrashService) async throws {
        let outcome = await log.load()
        guard let records = outcome.records else {
            throw CommandFailure("Peel couldn't read its History.\(outcome.problem.map { " \($0.summary)" } ?? "")")
        }
        let batch = try Self.batch(matching: id, in: Batch.all(in: records))
        let going = batch.restorable
        guard !going.isEmpty else {
            throw CommandFailure("Nothing of that removal is in the Trash anymore, so there is nothing to put back.")
        }

        Output.table(going.map { [Output.size($0.size), Output.path($0.originalURL)] })
        Output.line("Total: \(Output.size(going.totalSize))")
        if going.count < batch.records.count {
            Output.note("\(Output.count(batch.records.count - going.count, "item is", "items are")) no longer in the Trash and will stay as they are.")
        }

        guard !dryRun else {
            Output.line("Dry run: nothing was moved.")
            return
        }
        if !yes {
            try Output.confirm("Put \(Output.count(going.count, "item", "items")) back?")
        }

        // Ctrl-C and SIGTERM are ignored until History is written: an interrupt after the first item goes back
        // would leave History listing items as removed when they are already back in place.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        var restored: Set<UUID> = []
        var failures: [(RemovalRecord, RestoreFailure)] = []
        for record in going {
            // `peel` never uses the helper: items that need administrator access are left for the Peel app.
            if let failure = await service.restore(record.trashedItem, canUseHelper: false) {
                failures.append((record, failure))
            } else {
                restored.insert(record.id)
            }
        }
        let forgotten = await log.remove(restored).records != nil
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        Output.line("Put \(Output.count(restored.count, "item", "items")) back.")
        if !forgotten {
            Output.note("Peel couldn't write this to its History, so it may offer to put these back again.")
        }
        guard failures.isEmpty else {
            for (record, failure) in failures {
                Output.note("Couldn't put \(Output.path(record.originalURL)) back: \(failure.summary)")
            }
            throw ExitCode.failure
        }
    }
}
