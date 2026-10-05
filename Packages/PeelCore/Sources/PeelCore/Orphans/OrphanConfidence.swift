public import Foundation

/// How sure Peel is that nothing uses a group of orphaned files anymore, and why.
///
/// It never changes what Peel offers: orphaned files are never selected for the user, whatever this says. It
/// decides how a row reads, which rows are listed first, and that Peel recommends nothing in a group it is unsure of.
public struct OrphanConfidence: Sendable, Hashable {
    public enum Level: Int, Sendable, Hashable, Comparable {
        /// Something may still use the files: it is running, it wrote here recently or after the app was gone, or
        /// another app by the same maker is installed.
        case unsure
        /// Nothing installed claims it.
        case likely
        /// Nothing claims it, and Peel knows why: it saw the app go and nothing wrote here after, nothing has
        /// written here in months, or the files are links into an app that is gone.
        case certain

        public static func < (one: Level, other: Level) -> Bool { one.rawValue < other.rawValue }
    }

    public enum Reason: Sendable, Hashable {
        /// Peel saw the app installed, and then saw it gone.
        case appLeft(name: String, lastSeen: Date)
        /// Nothing has written here in this many whole months.
        case untouched(months: Int)
        /// Something wrote here within the last week, so something may still be running.
        case writtenRecently(Date)
        /// Something wrote here after Peel last saw the app, later than its removal takes, so something may still
        /// use the files: the app itself from another disk, or another program.
        case writtenAfterItLeft(name: String, written: Date)
        /// An app by the same maker is still installed, and apps by one maker can share group folders.
        case sameMakerStillInstalled
        /// Something with this identifier is running right now.
        case running
        /// Links into an app that is gone, so they lead nowhere.
        case leadsIntoAnAppThatIsGone
        /// Only the name of an app Peel saw installed ties these files to it.
        case onlyTheName(of: String)
        /// Nothing installed claims the identifier, which is all Peel can say.
        case nothingClaimsIt
    }

    /// A write this recent means something may still be running. A week covers a Mac left unused over a weekend.
    public static let recentlyWritten: TimeInterval = 7 * 24 * 60 * 60
    /// How long after Peel last saw an app a write still counts as part of its removal.
    public static let settling: TimeInterval = 24 * 60 * 60
    /// Months without a write after which Peel is sure the files are abandoned.
    public static let longUntouched = 6

    public let level: Level
    public let reasons: [Reason]

    /// Judges how sure Peel can be that nothing uses `group`, from the signals the scan already gathered.
    ///
    /// A sign that something still uses the files outranks a sign that nothing does. Helpers, agents, and
    /// command-line tools keep folders that no app bundle claims, and another app by the same maker may still
    /// read what the two apps shared.
    public static func judge(
        _ group: OrphanGroup,
        installedTeams: Set<String> = [],
        running: Set<String> = [],
        now: Date = .now
    ) -> OrphanConfidence {
        if running.contains(where: { isOneApp($0.lowercased(), group.identifier.lowercased()) }) {
            return OrphanConfidence(level: .unsure, reasons: [.running])
        }
        // Links into an app that is gone lead nowhere, whatever their dates or the maker's other apps suggest.
        if group.items.allSatisfy({ $0.kind == .commandLineTools }) {
            return OrphanConfidence(level: .certain, reasons: [.leadsIntoAnAppThatIsGone])
        }
        if let app = group.rememberedApp, group.items.allSatisfy({ $0.namedAfter != nil }) {
            return OrphanConfidence(level: .unsure, reasons: [.onlyTheName(of: app.name)])
        }
        let makerIsStillHere = group.rememberedApp?.teamIdentifier.map(installedTeams.contains) ?? false
        // A folder's own date changes when files are taken out of it, so the last write on a leftover is often
        // the uninstall itself. If nothing was written later than `settling` after Peel last saw the app, a
        // recent date is the removal, not a sign that something still uses the folder.
        if !makerIsStillHere, let app = group.rememberedApp, let written = lastWrite(in: group),
           written <= app.lastSeen.addingTimeInterval(settling) {
            return OrphanConfidence(level: .certain, reasons: [.appLeft(name: app.name, lastSeen: app.lastSeen)])
        }
        if let written = group.lastModified, now.timeIntervalSince(written) < recentlyWritten, written <= now {
            return OrphanConfidence(level: .unsure, reasons: [.writtenRecently(written)])
        }
        if makerIsStillHere {
            return OrphanConfidence(level: .unsure, reasons: [.sameMakerStillInstalled])
        }

        if let months = monthsUntouched(group, now: now), months >= longUntouched {
            return OrphanConfidence(level: .certain, reasons: [.untouched(months: months)])
        }
        guard let app = group.rememberedApp else {
            return OrphanConfidence(level: .likely, reasons: [.nothingClaimsIt])
        }
        // Peel saw the app go, and something wrote here later than its removal takes, or when is not known.
        if let written = lastWrite(in: group), written <= now {
            return OrphanConfidence(level: .unsure, reasons: [.writtenAfterItLeft(name: app.name, written: written)])
        }
        return OrphanConfidence(level: .likely, reasons: [.appLeft(name: app.name, lastSeen: app.lastSeen)])
    }

    /// Whether two identifiers belong to one app. A helper runs under its app's identifier or a longer one. A
    /// prefix counts only with three components or more, since two name a maker, not an app.
    static func isOneApp(_ one: String, _ other: String) -> Bool {
        if one == other { return true }
        let (short, long) = one.count < other.count ? (one, other) : (other, one)
        return Identifier.componentCount(of: short) >= 3 && long.hasPrefix(short + ".")
    }

    /// The group's last write, or nil when an item was not measured in time: what is inside it was not read.
    static func lastWrite(in group: OrphanGroup) -> Date? {
        group.total.isComplete ? group.lastModified : nil
    }

    /// Whole months since the group's last write, from the items whose date moves when they are used: code macOS
    /// loads keeps its date, so a group of plug-ins alone says nothing this way.
    static func monthsUntouched(_ group: OrphanGroup, now: Date) -> Int? {
        let used = group.items.filter { !$0.kind.isLoadedCode }
        guard group.total.isComplete, let written = used.compactMap(\.modificationDate).max(), written <= now else {
            return nil
        }
        // Counts Gregorian months, whatever calendar the user has set. In a lunar calendar, the default in Saudi
        // Arabia, six months end several days sooner.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let months = calendar.dateComponents([.month], from: written, to: now).month
        return months.map { max(0, $0) }
    }
}
