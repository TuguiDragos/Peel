public import Foundation

public enum MatchReason: String, Sendable, Hashable {
    case bundleIdentifier
    case embeddedBundleIdentifier
    case applicationGroup
    case bundleIdentifierPrefix
    case name
    case teamIdentifier
    case vendorPrefix
    case namePrefix
    /// A launchd job whose program sits inside the app, whatever the file is called.
    case launchdJob
    /// A link in `/usr/local/bin` or `/usr/local/sbin` that leads to a tool inside the app.
    case linksToTheApp
    /// An installer receipt for this app's identifier, which keeps macOS counting the package as installed.
    case installerReceipt
    /// The app's Homebrew cask lists this path in its uninstall or zap stanza.
    case homebrewCask
}

public enum MatchConfidence: Int, Sendable, Hashable, Comparable {
    case possible
    case likely
    case certain

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why an item Peel would otherwise select is shown and left alone. The row gives the reason, so the user can
/// tell a deliberate choice from an oversight.
public enum HoldBack: String, Sendable, Hashable {
    /// A repository inside, so the folder may carry work that was committed and never pushed anywhere.
    case holdsRepository
    /// `/Users/Shared`, which belongs to every account on the Mac rather than to one app.
    case sharedWithEveryone
    /// Claimed on nothing but the app's name (or an identifier that is only a word), in the home folder or at the
    /// top of a Library, where a name alone is only a guess.
    case namedLikeTheApp
    /// Something the user excluded is inside, so the whole item stays.
    case holdsAnExclusion
    /// The folder did not answer in time, so neither its size nor what it holds is known.
    case notMeasured
    /// macOS refused to let Peel read inside, so what the folder holds is not known, and zero would be a wrong
    /// size. From macOS 27, another team's container is refused outright rather than prompted for.
    case couldNotBeRead
    /// A sandboxed app's container whose `Data/Documents` is not empty or cannot be read. That is where the app
    /// keeps what the user made, and `RemovalGuard` refuses to move it.
    case holdsDocuments
    /// A photo, music, or video library is inside, and `RemovalGuard` refuses to move the folder around one.
    case holdsALibrary
    /// A cryptocurrency wallet or a signing key is inside, which may exist nowhere else.
    case holdsAWallet
    /// A wallet or a key `ProtectedData` names is inside, and `RemovalGuard` refuses to move the folder around it.
    case holdsKeys
    /// Claimed on the app's name (or an identifier that is only a word), inside a folder that belongs to another
    /// installed app or to Apple. It is probably the other app's data about this one, as a documentation browser
    /// or a controller app keeps.
    case insideAnotherAppsFolder
    /// Needs an administrator, and the helper's own rule refuses it (`HelperReach`).
    case beyondTheHelper
    /// A cache macOS keeps for its own services, which may be using it at any moment (`SystemCaches`).
    case keptByMacOS
    /// A copy Mail keeps of an attachment that was opened. One that was edited may exist nowhere else.
    case openedFromMail
    /// A report macOS wrote when the app crashed, which its developer may still ask for.
    case crashReport
    /// A file in iCloud Drive, which moving to the Trash removes from every device.
    case inTheCloud
    /// A file a program has open right now, which may still be downloading it.
    case openInAProgram
    /// A download that changed within the last day, which may still be going.
    case changedRecently
    /// An installer package in a folder an app keeps in Application Support, which the app may still need.
    case keptByAnApp
    /// An update whose app is running, which may install it when it quits.
    case appIsRunning

    /// True when the item cannot be selected at all, rather than only left unselected.
    public var cannotBeMoved: Bool {
        self == .holdsDocuments || self == .holdsALibrary || self == .holdsKeys || self == .beyondTheHelper
    }

    /// Why what a walk saw leaves a folder to be chosen by hand: a wallet, a signing key, or a repository inside may
    /// exist nowhere else, and a folder the walk could not see into is not known to be empty.
    static func seen(in contents: FolderContents?) -> HoldBack? {
        guard let contents else { return .notMeasured }
        if contents.couldNotBeRead { return .couldNotBeRead }
        if contents.holdsWallet { return .holdsAWallet }
        return contents.holdsRepository ? .holdsRepository : nil
    }
}

public struct LeftoverMatch: Sendable, Hashable {
    public let reason: MatchReason
    public let confidence: MatchConfidence
    /// Bundle identifiers of other installed apps that match the item equally well.
    public let sharedWith: [String]
    /// Other copies of the app, wherever they are, that use the item too. They share its identifier, so each is
    /// known by its place.
    public let otherCopies: [URL]
    /// The reason the item was left unselected on purpose, if it was.
    public var heldBack: HoldBack?
    /// True when `reason` is an identifier that is a single word, such as `notes`. A bundle writes its own
    /// identifier, so such a claim says no more than a name.
    public let isAWord: Bool

    public init(
        reason: MatchReason,
        confidence: MatchConfidence,
        sharedWith: [String],
        otherCopies: [URL] = [],
        heldBack: HoldBack? = nil,
        isAWord: Bool = false
    ) {
        self.reason = reason
        self.confidence = confidence
        self.sharedWith = sharedWith
        self.otherCopies = Set(otherCopies).sorted { $0.path(percentEncoded: false) < $1.path(percentEncoded: false) }
        self.heldBack = heldBack
        self.isAWord = isAWord
    }

    public var isShared: Bool { !sharedWith.isEmpty || !otherCopies.isEmpty }

    /// True when the claim is the app's name, or an identifier that is only a word.
    public var restsOnAName: Bool { reason == .name || isAWord }

    /// True when the item belongs to this app alone. Holding it back does not change that: a container held
    /// back for the documents inside is still the app's, and a reset still clears the settings beside them.
    public var isTheAppsAlone: Bool { !isShared && confidence >= .likely }

    public var isRecommended: Bool { isTheAppsAlone && heldBack == nil }

    /// Returns the same match, held back for `heldBack`: shown, but never selected.
    public func forReview(_ heldBack: HoldBack) -> LeftoverMatch {
        LeftoverMatch(reason: reason, confidence: confidence, sharedWith: sharedWith, otherCopies: otherCopies, heldBack: heldBack, isAWord: isAWord)
    }

    /// Returns the same match, no surer than `ceiling`.
    func atMost(_ ceiling: MatchConfidence) -> LeftoverMatch {
        LeftoverMatch(
            reason: reason, confidence: min(confidence, ceiling), sharedWith: sharedWith, otherCopies: otherCopies,
            heldBack: heldBack, isAWord: isAWord
        )
    }

    /// Combines two apps' claims on one item, cautiously and the same in either order: the weaker claim counts,
    /// and if either one is held back, so is the result.
    func combined(with other: LeftoverMatch) -> LeftoverMatch {
        let weaker = [self, other].min { lhs, rhs in
            lhs.confidence != rhs.confidence ? lhs.confidence < rhs.confidence : lhs.reason.rawValue < rhs.reason.rawValue
        } ?? self
        // A reason that blocks the move outranks one that only leaves the item unselected.
        let heldBack = [heldBack, other.heldBack].compactMap(\.self).min { lhs, rhs in
            lhs.cannotBeMoved != rhs.cannotBeMoved ? lhs.cannotBeMoved : lhs.rawValue < rhs.rawValue
        }
        return LeftoverMatch(
            reason: weaker.reason,
            confidence: weaker.confidence,
            sharedWith: Set(sharedWith).union(other.sharedWith).sorted(),
            otherCopies: otherCopies + other.otherCopies,
            heldBack: heldBack,
            isAWord: isAWord || other.isAWord
        )
    }
}

public struct Leftover: Sendable, Hashable, Identifiable {
    public let url: URL
    public let kind: SearchLocation.Kind
    public let match: LeftoverMatch
    public let size: Int64
    /// False for what did not answer in time or could not be read: `size` is then zero and means nothing.
    public let isMeasured: Bool
    public let requiresPrivileges: Bool
    /// True for a preference file that is no property list (`PreferenceFile.isDamaged`).
    public var holdsDamagedSettings = false

    public var id: URL { url }

    /// Returns the same leftover, held back for `reason`: shown, but never selected. A reason that already blocks
    /// the move stays, since it outranks one that only leaves the item unselected.
    func heldBack(_ reason: HoldBack) -> Leftover {
        guard match.heldBack?.cannotBeMoved != true else { return self }
        return Leftover(
            url: url, kind: kind, match: match.forReview(reason), size: size, isMeasured: isMeasured,
            requiresPrivileges: requiresPrivileges, holdsDamagedSettings: holdsDamagedSettings
        )
    }
}

extension Leftover {
    /// The order every list of leftovers keeps: what could not be measured first, since it is most likely the
    /// biggest, then the largest, then by path.
    static func comesBefore(_ lhs: Leftover, _ rhs: Leftover) -> Bool {
        if lhs.isMeasured != rhs.isMeasured { return !lhs.isMeasured }
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        return lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
    }
}

public struct LeftoverScan: Sendable {
    public let leftovers: [Leftover]
    public let unreadableLocations: [SearchLocation]
    /// Locations where the search inside other folders hit its limit, so some of the app's files may be missed.
    public var cutShortLocations: [SearchLocation] = []

    /// Holds back, as `beyondTheHelper`, each item that needs an administrator and that the helper would refuse
    /// once `app` has moved. An item already held back by `holdsAnExclusion`, or by a reason that blocks the move,
    /// keeps its reason.
    func holdingBack(beyond reach: HelperReach, leaving app: URL) -> LeftoverScan {
        LeftoverScan(
            leftovers: leftovers.map { leftover in
                let heldBack = leftover.match.heldBack
                guard
                    leftover.requiresPrivileges, heldBack != .holdsAnExclusion,
                    reach.isBeyond(leftover.url, leaving: app)
                else { return leftover }
                return leftover.heldBack(.beyondTheHelper)
            },
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations
        )
    }

    /// Adds findings the scanner didn't see, keeping what it already knows about a path.
    public func adding(_ extra: [Leftover]) -> LeftoverScan {
        // By what each item is on the disk, not by its spelling: a cask can write a folder in another case, or with
        // a slash at the end, and it is still the folder the scan found.
        let known = Set(leftovers.map { ItemKey($0.url) })
        let merged = leftovers + extra.filter { !known.contains(ItemKey($0.url)) }
        return LeftoverScan(
            leftovers: merged.sorted(by: Leftover.comesBefore),
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations
        )
    }
}
