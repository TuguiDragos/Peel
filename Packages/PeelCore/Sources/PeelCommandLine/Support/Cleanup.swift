import ArgumentParser
import Foundation
import PeelCore

/// A removal from the command line, once a command has worked out what would move. Every command that removes
/// goes through here, so they all ask, record, and exit the same way. The tool never uses the privileged helper,
/// so an item that needs administrator access stays, and the list says why.
struct Cleanup {
    struct Item {
        let url: URL
        /// Nil when the size isn't known, as for a folder that didn't answer in time. It is never shown as zero.
        let size: Int64?
        /// Why the item stays, or nil when it moves: the removal guard's answer, or `.needsHelper`.
        let refusal: TrashFailure.Reason?
    }

    let items: [Item]
    let source: String
    /// `"tool"` when `source` is the tool's own name, so the app's History can show it in the user's language.
    var sourceKey: String?
    let tool: String

    var moving: [Item] { items.filter { $0.refusal == nil } }
    var staying: [Item] { items.filter { $0.refusal != nil } }
    var total: SizeTotal { SizeTotal(moving.map(\.size)) }

    /// Builds a cleanup, judging each item before anything is printed, so the list shows what the move will
    /// really do.
    static func of(
        _ items: [(url: URL, size: Int64?)],
        source: String,
        sourceKey: String? = nil,
        tool: String,
        needingAdministrator: Set<URL> = [],
        service: TrashService
    ) -> Cleanup {
        Cleanup(
            items: items.map {
                Item(
                    url: $0.url,
                    size: $0.size,
                    refusal: needingAdministrator.contains($0.url) ? .needsHelper : service.refusal(of: $0.url)
                )
            },
            source: source,
            sourceKey: sourceKey,
            tool: tool
        )
    }

    static func refuseJSON() throws {
        throw ValidationError("--json lists what is there. Leave --remove off to get the list, or leave --json off to move it.")
    }

    /// Prints the list and, unless `dryRun` is set, asks, moves what can go, and records it in History. A declined
    /// answer exits 2, and a failed move exits 1.
    func run(
        question: String,
        dryRun: Bool,
        yes: Bool,
        using service: TrashService,
        recordingIn log: RemovalLog = RemovalLog(),
        refusals: RefusalLog = RefusalLog(),
        move: (TrashService, [URL]) async -> TrashResult = { await $0.trash($1) }
    ) async throws {
        // A third column, saying which items move and why the others stay, appears only when some item stays.
        let saysWhyItStays = !staying.isEmpty
        Output.table(items.map { item in
            [Output.size(item.size), Output.path(item.url)] + (saysWhyItStays ? [item.refusal.map { "stays: \($0.summary)" } ?? "moves"] : [])
        })
        Output.line("Total: \(Output.size(total))")

        guard !dryRun else {
            Output.line(moving.isEmpty ? "Nothing here can be moved." : "Dry run: nothing was moved.")
            return
        }
        // Refused items never reach the move, so their failures are built here and recorded, just as the app
        // records the refusals its service reports.
        let refused = items.compactMap { item in item.refusal.map { TrashFailure(url: item.url, reason: $0) } }
        guard !moving.isEmpty else {
            Output.line("Nothing here can be moved.")
            await refusals.add(refused, source: source, tool: tool)
            return
        }
        if !yes {
            try Output.confirm(question)
        }

        // Ctrl-C and SIGTERM are ignored until History is written: an interrupt after the first move would
        // leave items in the Trash that History knows nothing about.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let result = await move(service, moving.map(\.url))
        let sizes = Dictionary(items.map { ($0.url, $0.size ?? 0) }, uniquingKeysWith: { first, _ in first })
        let recorded = await Removals.record(
            TrashResult(trashed: result.trashed, failures: result.failures + refused),
            from: source,
            key: sourceKey,
            sizes: sizes,
            tool: tool,
            in: log,
            refusals: refusals
        )
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        Output.line("Moved \(Output.count(result.trashed.count, "item", "items")) to the Trash.")
        if !recorded {
            Output.note("Peel couldn't write this to its History, so drag these back out of the Trash in Finder if you need to.")
        }
        guard result.failures.isEmpty else {
            for failure in result.failures {
                Output.note("\(Output.path(failure.url)) stayed: \(failure.reason.summary)")
            }
            throw ExitCode.failure
        }
    }
}
