public import Foundation
internal import PeelPrivileged

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
    /// A browser's native messaging manifest whose program sits inside the app.
    case nativeMessagingHost
    /// An installer receipt for this app's identifier, which keeps macOS counting the package as installed.
    case installerReceipt
    /// The folder of the Homebrew cask that installed the app, which keeps Homebrew counting it as installed.
    case homebrewReceipt
    /// A link Homebrew made that leads into that folder, such as the command it puts on the path.
    case leadsIntoItsHomebrewReceipt
    /// The app's Homebrew cask lists this path in its uninstall or zap stanza.
    case homebrewCask
    /// What an area the app manages keeps in the home folder, such as the simulators Xcode makes
    /// (`SpaceInventory.Definition.managedBy`).
    case managedByTheApp
    /// The folder the app's own settings name for what its updater downloads (`InstalledApp.updaterFolder`).
    case updaterDownloads
    /// A folder the app's own product file names for its data (`InstalledApp.productFolders`).
    case namedByTheApp
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
    /// Git tracks files inside, so the folder is part of the project rather than something a build makes again.
    case trackedByGit
    /// Inside a Git repository whose index could not be read, so whether Git tracks files inside is not known.
    case gitTrackingNotKnown
    /// Reading which files Git tracks there took longer than its budget, so that is not known until a later scan.
    case gitTrackingNotReadInTime
    /// A build folder that also keeps the options its build was set up with, which nothing else in the project holds.
    case keepsItsSetup
    /// `/Users/Shared`, which belongs to every account on the Mac rather than to one app.
    case sharedWithEveryone
    /// A folder a package made, offered whole while it holds what something else put there: another package's
    /// files, or the person's own.
    case holdsWhatOthersPut
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
    /// Its permissions kept Peel from reading inside, as with a folder only root may open, so what it holds is not
    /// known. Full Disk Access doesn't open such a folder.
    case closedByPermissions
    /// macOS would not let Peel list a folder inside it, so `RemovalGuard` refuses to move it as the person: what it
    /// never moves may be in there (`GuardRefusal.couldNotLookInside`).
    case couldNotLookInside
    /// A sandboxed app's container whose `Data/Documents` is not empty or cannot be read. That is where the app
    /// keeps what the user made, and `RemovalGuard` refuses to move it.
    case holdsDocuments
    /// A photo, music, or video library is inside, and `RemovalGuard` refuses to move the folder around one.
    case holdsALibrary
    /// A cryptocurrency wallet or a signing key is inside, which may exist nowhere else.
    case holdsAWallet
    /// A password database or its key file is inside, which may exist nowhere else.
    case holdsAPasswordDatabase
    /// Mail kept on this Mac may be inside, such as a local or POP account's (`KeptOnlyHere`).
    case holdsLocalMail
    /// Message history that may exist only on this Mac (`KeptOnlyHere`).
    case holdsMessageHistory
    /// Passwords or sign-in codes that may exist only on this Mac (`KeptOnlyHere`).
    case holdsPasswordsOrCodes
    /// VPN connections, with their keys and certificates, that may exist only on this Mac (`KeptOnlyHere`).
    case holdsVPNConnections
    /// A sign-in to a service a tool saved when the person logged in, such as a registry token (`KeptOnlyHere`).
    case holdsSignIns
    /// A torrent client's list of the torrents added to it and how far each one got (`KeptOnlyHere`).
    case holdsTorrents
    /// What the person made with the app, such as saved games, databases, or the app's own backups, that may exist
    /// only on this Mac (`KeptOnlyHere`).
    case holdsWorkMadeWithTheApp
    /// Simulators, with the apps installed in them and their data, which may exist only on this Mac.
    case holdsSimulators
    /// A wallet or a key `ProtectedData` names is inside, and `RemovalGuard` refuses to move the folder around it.
    case holdsKeys
    /// Work kept nowhere else is inside a cache folder, such as an editor's local history of the person's files, and
    /// `RemovalGuard` refuses to move the folder around it (`ProtectedData.holdsWorkKeptInACache`).
    case holdsWorkKeptInACache
    /// Claimed on the app's name (or an identifier that is only a word), inside a folder that belongs to another
    /// installed app or to Apple. It is probably the other app's data about this one, as a documentation browser
    /// or a controller app keeps.
    case insideAnotherAppsFolder
    /// Holds what another installed app keeps as its own, as Developer's table names it, such as Xcode's folders in
    /// `~/Library/Developer`: it goes with that app, never with this one.
    case holdsAnotherAppsData
    /// Needs an administrator, and the helper's own rule refuses it (`HelperReach`).
    case beyondTheHelper
    /// Removed by the app's own uninstaller once the app has moved (`UninstallsItself`). Moved first, the file of
    /// the job that runs the uninstaller would stop it, and the rest of its cleanup would never happen.
    case leftToItsUninstaller
    /// The copy macOS installed of an app's system extension, which only macOS removes.
    case systemExtension
    /// A system extension macOS removes at the next restart.
    case systemExtensionGoingAtRestart
    /// The copy macOS installed of a system extension that System Settings deletes (`systemSettingsDeletesIt`).
    case deletableSystemExtension
    /// An authorization plug-in macOS may load at login (`SignInPlugIns`), left to its maker's uninstaller.
    case signInPlugIn
    /// What macOS keeps for its own services, which may be using it at any moment (`MacOSsOwnItems`).
    case keptByMacOS
    /// A copy Mail keeps of an attachment that was opened. One that was edited may exist nowhere else.
    case openedFromMail
    /// A report macOS wrote when the app crashed, which its developer may still ask for.
    case crashReport
    /// It syncs to the person's other devices (`SyncedFolders`), so `RemovalGuard` refuses to move it.
    case inTheCloud
    /// A file a program has open right now, which may still be downloading it.
    case openInAProgram
    /// A disk image attached right now, which macOS holds open until it is ejected.
    case attachedDiskImage
    /// A download that changed within the last day, which may still be going.
    case changedRecently
    /// A `.part` file no browser left, which a program that resumes downloads, such as a torrent client, may still
    /// finish.
    case mayStillBeResumed
    /// A cache something wrote to in the last few minutes, which a program may still be using.
    case writtenRecently
    /// The folder of a server that still listens on the port it is named for, which keeps its uploads there.
    case serverStillListens
    /// An installer package in a folder an app keeps in Application Support, which the app may still need.
    case keptByAnApp
    /// A receipt whose package also left items outside the app, which Package Receipts lists only while it stays.
    case packageLeftMore
    /// An update whose app is running, which may install it when it quits.
    case appIsRunning
    /// An installer outside Downloads that is no installed app's, which may be the person's own rather than a download.
    case mayBeTheOnlyCopy
    /// An encrypted disk image, which holds what the person put in it.
    case encryptedImage

    /// True when the item cannot be selected at all, rather than only left unselected: the guard or the helper
    /// would refuse to move it.
    public var cannotBeMoved: Bool {
        self == .holdsDocuments || self == .holdsALibrary || self == .holdsKeys || self == .holdsWorkKeptInACache
            || self == .couldNotLookInside
            || self == .beyondTheHelper || self == .leftToItsUninstaller
            || self == .systemExtension || self == .systemExtensionGoingAtRestart || self == .deletableSystemExtension
            || self == .signInPlugIn
            || self == .holdsAnExclusion
            || self == .inTheCloud || self == .holdsAnotherAppsData
    }

    /// Why what a walk saw leaves a folder to be chosen by hand: a wallet, a signing key, or a repository inside may
    /// exist nowhere else, and a folder the walk could not see into is not known to be empty.
    static func seen(in contents: FolderContents?) -> HoldBack? {
        guard let contents else { return .notMeasured }
        if contents.couldNotBeRead { return unread(contents) }
        return secret(in: contents) ?? (contents.holdsRepository ? .holdsRepository : nil)
    }

    /// Why a folder the walk couldn't see all through is held back: closed by its permissions, or refused otherwise.
    static func unread(_ contents: FolderContents) -> HoldBack {
        contents.closedByPermissions ? .closedByPermissions : .couldNotBeRead
    }

    /// A wallet, a signing key, or a password database seen inside.
    static func secret(in contents: FolderContents) -> HoldBack? {
        if contents.holdsWallet { return .holdsAWallet }
        return contents.holdsPasswordDatabase ? .holdsAPasswordDatabase : nil
    }

    /// How long after a write a program may still be using what it wrote (`writtenRecently`).
    static let stillInUse: TimeInterval = 15 * 60

    /// Whether something wrote to `url` within `stillInUse`. The folder's own date counts too: it moves when an entry
    /// is added or removed.
    static func wasWrittenRecently(_ url: URL, contents: FolderContents?) -> Bool {
        let own = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let written = [own, contents?.newestChange].compactMap(\.self).max() else { return false }
        return Date.now.timeIntervalSince(written) < stillInUse
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
        LeftoverMatch(
            reason: reason,
            confidence: confidence,
            sharedWith: sharedWith,
            otherCopies: otherCopies,
            heldBack: heldBack,
            isAWord: isAWord
        )
    }

    /// Returns the same match, shared with `apps` as well.
    func sharing(with apps: [String]) -> LeftoverMatch {
        LeftoverMatch(
            reason: reason, confidence: confidence, sharedWith: Set(sharedWith).union(apps).sorted(),
            otherCopies: otherCopies, heldBack: heldBack, isAWord: isAWord
        )
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
            lhs.confidence != rhs.confidence
                ? lhs.confidence < rhs.confidence
                : lhs.reason.rawValue < rhs.reason.rawValue
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
    /// True when only an administrator can move it, from a place the helper may not move it from, and nothing else
    /// holds it back.
    public var isLeftForAnAdministrator = false

    public var id: URL { url }

    func sharing(with apps: [String]) -> Leftover {
        Leftover(
            url: url, kind: kind, match: match.sharing(with: apps), size: size, isMeasured: isMeasured,
            requiresPrivileges: requiresPrivileges, holdsDamagedSettings: holdsDamagedSettings,
            isLeftForAnAdministrator: isLeftForAnAdministrator
        )
    }

    /// Returns the same leftover, held back for `reason`: shown, but never selected. A reason that already blocks
    /// the move stays, since it outranks one that only leaves the item unselected.
    func heldBack(_ reason: HoldBack) -> Leftover {
        guard match.heldBack?.cannotBeMoved != true else { return self }
        return Leftover(
            url: url, kind: kind, match: match.forReview(reason), size: size, isMeasured: isMeasured,
            requiresPrivileges: requiresPrivileges, holdsDamagedSettings: holdsDamagedSettings,
            isLeftForAnAdministrator: isLeftForAnAdministrator
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
    /// True when macOS's privacy protection, not ordinary permissions, kept Peel out of one of `unreadableLocations`,
    /// so Full Disk Access would open it.
    public var needsFullDiskAccess = false

    /// Holds back, as `beyondTheHelper`, each item that needs an administrator and that the helper would refuse
    /// once `app` has moved. An item already held back by a reason that blocks the move keeps its reason, and one
    /// held back for nothing else is left for an administrator.
    func holdingBack(beyond reach: HelperReach, leaving app: URL) -> LeftoverScan {
        LeftoverScan(
            leftovers: leftovers.map { leftover in
                guard leftover.requiresPrivileges, reach.isBeyond(leftover.url, leaving: app) else { return leftover }
                var held = leftover.heldBack(.beyondTheHelper)
                held.isLeftForAnAdministrator = leftover.match.heldBack == nil
                return held
            },
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }

    /// The same scan, each item holding a place another installed app keeps (`places`) left alone and shared with it.
    func holdingBack(placesOthersKeep places: [(place: String, app: String)]) -> LeftoverScan {
        LeftoverScan(
            leftovers: leftovers.map { leftover in
                let item = PathPattern.comparablePath(of: leftover.url)
                let keepers = Set(places.filter { PathComponents.isPath($0.place, atOrInside: item) }.map(\.app))
                guard !keepers.isEmpty else { return leftover }
                return leftover.sharing(with: keepers.sorted()).heldBack(.holdsAnotherAppsData)
            },
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }

    func holdingBack(signInPlugInsUnder root: URL) -> LeftoverScan {
        LeftoverScan(
            leftovers: leftovers.map { SignInPlugIns.isOne($0.url, root: root) ? $0.heldBack(.signInPlugIn) : $0 },
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }

    func leavingToItsUninstaller(_ app: UninstallsItself) -> LeftoverScan {
        LeftoverScan(
            leftovers: leftovers.map { app.removes($0.url) ? $0.heldBack(.leftToItsUninstaller) : $0 },
            unreadableLocations: unreadableLocations,
            cutShortLocations: cutShortLocations,
            needsFullDiskAccess: needsFullDiskAccess
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
            cutShortLocations: cutShortLocations,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }
}
