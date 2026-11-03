public import Foundation
import Synchronization

public struct UpdateChecker: Sendable {
    /// Raised whenever the checker answers some apps differently: an app an earlier revision couldn't check is asked
    /// again rather than waited out, and so is one this revision asks nobody about (`UpdateMemory.recalled`).
    public static let revision = 5

    /// The largest reply read. An update feed is a small XML, YAML, or JSON file, and its address comes from
    /// the app's own bundle, so the server is not trusted to keep its reply small.
    static let maximumFeedBytes = 4 * 1_024 * 1_024

    /// Settings for Peel's own session, used instead of the shared one: no cookies, no cache, time limits, and
    /// headers of its own. A feed server should not set a cookie, read one left by another app's check, get back a
    /// validator it could make unique to this Mac, hold a connection open, or learn more than that Peel asks: the
    /// system's own headers would tell it Peel's build, the macOS build and the person's languages.
    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        // A Mac just awake from sleep has no network for a few seconds, and a check made then would fail at once.
        configuration.waitsForConnectivity = true
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Peel", "Accept-Language": "*"]
        return configuration
    }

    private let session: URLSession
    private let appStoreWindow: RequestWindow
    private let country: String
    private let systemVersion: String
    private let isAppleSilicon = HostArchitecture.isAppleSilicon
    /// The time a check is made at, which decides whether what Homebrew says is recent enough to count.
    private let clock: @Sendable () -> Date
    private let isOnline: @Sendable () async -> Bool
    private let replies = ReplyCount()

    public init(
        session: URLSession? = nil, locale: Locale = .current, clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(session: session, locale: locale, clock: clock, appStoreWindow: .appStore)
    }

    init(
        session: URLSession? = nil, locale: Locale = .current, clock: @escaping @Sendable () -> Date = { .now },
        appStoreWindow: RequestWindow, isOnline: @escaping @Sendable () async -> Bool = NetworkPath.isOnline
    ) {
        self.session = session ?? URLSession(configuration: Self.configuration)
        self.appStoreWindow = appStoreWindow
        self.clock = clock
        self.isOnline = isOnline
        country = Self.storefront(of: locale)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        systemVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The two-letter country of the App Store to ask. Apple's lookup refuses a numeric region such as 150
    /// (Europe) or 001 (World) with HTTP 400, so those, like a Mac with no region, use the United States store.
    static func storefront(of locale: Locale) -> String {
        let region = locale.region?.identifier.lowercased() ?? ""
        return region.count == 2 && region.allSatisfy({ $0.isASCII && $0.isLetter }) ? region : "us"
    }

    /// Returns the update status of `app`, without installing anything. `preference` decides which source to
    /// believe when an app can be updated in more than one way, `earlier` is the last answer about this build, and
    /// `notListedBefore` says the App Store's last answer about it listed no such app.
    @concurrent
    public func status(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = [],
        earlier: UpdateStatus? = nil,
        notListedBefore: Bool = false
    ) async -> UpdateStatus {
        await answer(
            for: app, preference: preference, casks: casks, earlier: earlier, notListedBefore: notListedBefore
        ).status
    }

    /// Returns the update status, and the developer's name when the App Store answered. An App Store app is
    /// signed by Apple, so its signature does not name the developer, but the store's record does.
    @concurrent
    public func answer(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = [],
        earlier: UpdateStatus? = nil,
        notListedBefore: Bool = false
    ) async -> UpdateAnswer {
        let homebrew = homebrewAnswer(for: app, casks: casks)
        if let status = Self.statusWithoutAsking(for: app, preference: preference, homebrew: homebrew) {
            return UpdateAnswer(status: status)
        }
        // Even with the App Store preferred, Apple is asked only about apps from the App Store. Any other app is
        // checked through its own feed, or not at all.
        let own = preference == .appStore && app.isFromAppStore
            ? await appStoreAnswer(for: app, earlier: earlier, notListedBefore: notListedBefore)
            : await feedAnswer(for: app, earlier: earlier, notListedBefore: notListedBefore)
        guard !own.wasOffline else { return own }
        // A feed can be down, and the App Store may not sell the app here: what Homebrew knows is used then.
        if let status = homebrew.status, own.status == .unsupported || own.status == .failed {
            return UpdateAnswer(
                status: status, developer: own.developer, standsInFor: own.status,
                reachedNoServer: own.reachedNoServer, isNotListed: own.isNotListed, failure: own.failure
            )
        }
        return own
    }

    /// The status `answer` gives `app` without asking a server, from Homebrew's casks and the app's own files, or nil
    /// when its source must be asked. Where that source had no answer (`known`), Homebrew's counts, else `known`.
    public func statusWithoutAsking(
        for app: InstalledApp, preference: UpdateSource, casks: [HomebrewPackage], known: UpdateStatus? = nil
    ) -> UpdateStatus? {
        let homebrew = homebrewAnswer(for: app, casks: casks)
        if let status = Self.statusWithoutAsking(for: app, preference: preference, homebrew: homebrew) {
            return status
        }
        return known == .unsupported || known == .failed ? homebrew.status ?? known : nil
    }

    /// What Homebrew's catalog says comes after the app's own source, whatever is preferred: Homebrew can't upgrade a
    /// copy it didn't install, and the app's own updater is what that copy follows.
    private static func statusWithoutAsking(
        for app: InstalledApp, preference: UpdateSource, homebrew: (status: UpdateStatus?, isFromTheCatalog: Bool)
    ) -> UpdateStatus? {
        let asksNobody = asksNobody(about: app, preference: preference)
        let first = homebrew.isFromTheCatalog ? nil : homebrew.status
        switch preference {
        case .homebrew:
            // Where Homebrew can't tell, from what it installed or from its catalog, the app's own feed answers instead
            // of a false "up to date".
            return first ?? (asksNobody ? homebrew.status ?? .unsupported : nil)
        case .automatic, .developer, .appStore:
            if preference == .automatic, case .updateAvailable = first { return first }
            // An app from a cask may have no feed of its own: what Homebrew knows is used rather than "Can't check
            // for updates".
            return asksNobody ? homebrew.status ?? .unsupported : nil
        }
    }

    /// Whether a check of `app` has no server to ask: its bundle names no version or no feed, and it isn't an app
    /// from the App Store with the App Store preferred.
    private static func asksNobody(about app: InstalledApp, preference: UpdateSource) -> Bool {
        (app.version == nil || app.updateFeed == nil) && !(preference == .appStore && app.isFromAppStore)
    }

    /// Whether a check of `app` has no server to ask, whichever source is preferred.
    static func asksNobody(about app: InstalledApp) -> Bool {
        UpdateSource.allCases.allSatisfy { asksNobody(about: app, preference: $0) }
    }

    /// Homebrew's answer for `app`, found without a network request, or nil when it can't tell: for a copy Homebrew
    /// installed, from what it installed (`homebrewStatus(of:appVersion:at:)`), and for one it didn't, from the version
    /// its catalog lists (`catalogStatus(of:appVersion:at:)`).
    public func homebrewStatus(for app: InstalledApp, casks: [HomebrewPackage]) -> UpdateStatus? {
        homebrewAnswer(for: app, casks: casks).status
    }

    private func homebrewAnswer(
        for app: InstalledApp, casks: [HomebrewPackage]
    ) -> (status: UpdateStatus?, isFromTheCatalog: Bool) {
        if let cask = CaskEvidence.installedCask(for: app, in: casks) {
            return (Self.homebrewStatus(of: cask, appVersion: app.version, at: clock()), false)
        }
        let status = Self.catalogCask(for: app, in: casks).flatMap {
            Self.catalogStatus(of: $0, appVersion: app.version, at: clock())
        }
        return (status, true)
    }

    /// The cask Homebrew's catalog lists for `app` when Homebrew didn't install this copy: one its bundle proves
    /// (`CaskEvidence.proves`). An app from the App Store or Setapp, or one that came with macOS, is kept current by
    /// them, in versions of their own, so the catalog says nothing of it.
    public static func catalogCask(for app: InstalledApp, in casks: [HomebrewPackage]) -> HomebrewPackage? {
        guard !app.isFromAppStore, !app.isFromSetapp, !app.isSystemProtected,
              CaskEvidence.installedCask(for: app, in: casks) == nil
        else { return nil }
        return CaskEvidence.cask(for: app, in: casks)
    }

    /// What the version `cask` lists says at `now` of a copy Homebrew didn't install, at `appVersion`: an update when
    /// it is written with as many numbers and they are past the app's, since a catalog never lists an older version
    /// than it did, and up to date only as `isAlready` reads it, within a day of Homebrew's last check. Otherwise nil.
    static func catalogStatus(of cask: HomebrewPackage, appVersion: String?, at now: Date) -> UpdateStatus? {
        guard let appVersion, VersionComparison.isAVersion(appVersion), let latest = cask.latestVersion,
              cask.isStillUpgraded, latest != "latest"
        else { return nil }
        if VersionComparison.hasNewerNumbers(UpdateStatus.shownVersion(of: latest), than: appVersion) {
            return .updateAvailable(version: latest, source: .homebrew, releaseNotes: cask.homepage)
        }
        return isAlready(appVersion, at: latest) && isRecent(cask.lastUpdateCheck, at: now) ? .upToDate : nil
    }

    /// Why the version `cask` lists can't say at `now` whether a copy Homebrew didn't install, at `appVersion`, is up
    /// to date, when a later check of Homebrew's could: the cask lists no version to compare or Homebrew disabled it,
    /// or Homebrew last checked for new versions too long ago. Homebrew's settings for apps that update themselves
    /// don't count, since they decide only what Homebrew upgrades.
    static func whyTheCatalogCannotTell(
        about cask: HomebrewPackage, appVersion: String?, at now: Date
    ) -> HomebrewCannotTell.Reason? {
        if !cask.isStillUpgraded { return .disabled }
        if cask.latestVersion == "latest" { return .installsTheNewest }
        guard let latest = cask.latestVersion, isAlready(appVersion, at: latest) else { return nil }
        return isRecent(cask.lastUpdateCheck, at: now) ? nil : .notCheckedRecently
    }

    /// Whether Homebrew last checked for new versions at `checked`, less than `Homebrew.autoUpdateInterval` before
    /// `now`.
    private static func isRecent(_ checked: Date?, at now: Date) -> Bool {
        checked.map { now.timeIntervalSince($0) < Homebrew.autoUpdateInterval } ?? false
    }

    /// The status Homebrew reports at `now` for `cask`, known to be the app's at `appVersion`, or nil when it can't
    /// tell (`whyHomebrewCannotTell(about:at:)`), or when the app is behind and Homebrew can't upgrade it.
    static func homebrewStatus(of cask: HomebrewPackage, appVersion: String?, at now: Date) -> UpdateStatus? {
        if cask.isOutdated, let latest = cask.latestVersion, !isAlready(appVersion, at: latest) {
            return cask.waitsForAnUpgrade
                ? .updateAvailable(version: latest, source: .homebrew, releaseNotes: cask.homepage) : nil
        }
        return whyHomebrewCannotTell(about: cask, at: now) == nil ? .upToDate : nil
    }

    /// Why a cask Homebrew doesn't count outdated may still be behind at `now`: Homebrew compares no version for it, or
    /// it last checked for new versions longer ago than `Homebrew.autoUpdateInterval`, or when isn't known.
    static func whyHomebrewCannotTell(about cask: HomebrewPackage, at now: Date) -> HomebrewCannotTell.Reason? {
        if let reason = cask.whyHomebrewCannotCompare { return reason }
        return isRecent(cask.lastUpdateCheck, at: now) ? nil : .notCheckedRecently
    }

    /// Whether the app's own `version` is already the cask's `latest`, or past it. Homebrew counts a cask outdated by
    /// the version it installed, which an app that updated itself leaves behind, so the app is compared as Homebrew
    /// compares one that updates itself: with the part before a comma, and only a version of as many parts.
    static func isAlready(_ version: String?, at latest: String) -> Bool {
        guard let version else { return false }
        let tap = String(latest.prefix { $0 != "," })
        guard tap.split(separator: ".").count == version.split(separator: ".").count else { return false }
        return !VersionComparison.isNewer(tap, than: version)
    }

    /// Why Peel can't check `app`, for an app a check answered `.unsupported`.
    public func whyItCannotCheck(
        _ app: InstalledApp, preference: UpdateSource, casks: [HomebrewPackage]
    ) -> CannotCheck {
        if let silence = homebrewCannotTell(about: app, preference: preference, casks: casks) {
            return .homebrewCannotTell(silence)
        }
        if app.isSystemProtected { return .cameWithMacOS }
        if app.isFromSetapp { return .cameFromSetapp }
        if app.version == nil { return .namesNoVersion }
        if app.isFromAppStore {
            guard case .appStore(.iPhoneAndiPad(_, let store?)) = app.updateFeed else {
                return .notInTheAppStore(store: nil)
            }
            return .notInTheAppStore(store: store)
        }
        return .namesNoFeed
    }

    /// Whether an answer that came at `checked` may still be shown as true while nothing asks again: for
    /// `UpdateSchedule.longest`, the longest wait between two checks. An answer of unknown date doesn't hold.
    public func stillHolds(answeredAt checked: Date?) -> Bool {
        checked.map { clock().timeIntervalSince($0) <= UpdateSchedule.longest } ?? false
    }

    /// The cask `app` came from or its catalog lists, and why Homebrew can't tell, when only Homebrew could say whether
    /// the app is up to date and it has no answer (`homebrewStatus(for:casks:)`), so a check has none for the app.
    public func homebrewCannotTell(
        about app: InstalledApp, preference: UpdateSource, casks: [HomebrewPackage]
    ) -> HomebrewCannotTell? {
        let now = clock()
        guard Self.asksNobody(about: app, preference: preference) else { return nil }
        if let cask = CaskEvidence.installedCask(for: app, in: casks) {
            guard Self.homebrewStatus(of: cask, appVersion: app.version, at: now) == nil,
                  let reason = Self.whyHomebrewCannotTell(about: cask, at: now)
            else { return nil }
            return HomebrewCannotTell(cask: cask, reason: reason)
        }
        guard let cask = Self.catalogCask(for: app, in: casks),
              Self.catalogStatus(of: cask, appVersion: app.version, at: now) == nil,
              let reason = Self.whyTheCatalogCannotTell(about: cask, appVersion: app.version, at: now)
        else { return nil }
        return HomebrewCannotTell(cask: cask, reason: reason)
    }

    private func feedAnswer(
        for app: InstalledApp, earlier: UpdateStatus?, notListedBefore: Bool
    ) async -> UpdateAnswer {
        // An app whose bundle names no version has nothing to compare a release with, so nobody is asked.
        guard let installed = app.version else { return UpdateAnswer(status: .unsupported) }
        return switch app.updateFeed {
        case nil: UpdateAnswer(status: .unsupported)
        case .sparkle(let url): await sparkleAnswer(for: app, installed: installed, at: url)
        case .electron(let url): await electronAnswer(for: app, installed: installed, at: url)
        case .vsCode(let url): await vsCodeAnswer(installed: installed, at: url)
        case .appStore: await appStoreAnswer(for: app, earlier: earlier, notListedBefore: notListedBefore)
        }
    }

    private func sparkleAnswer(for app: InstalledApp, installed: String, at url: URL) async -> UpdateAnswer {
        let reply = await fetchReply(url)
        guard let data = reply.data else { return Self.answer(after: reply) }
        let item: AppcastItem
        switch Appcast.read(data, systemVersion: systemVersion, isAppleSilicon: isAppleSilicon) {
        case .unreadable: return Self.unreadable(reply)
        case .nothingForThisMac: return UpdateAnswer(status: .upToDate)
        case .latest(let latest): item = latest
        }
        guard let latest = item.displayVersion else { return Self.unreadable(reply) }
        let isNewer = if let version = item.version, let build = app.buildVersion {
            VersionComparison.isNewer(version, than: build)
        } else {
            VersionComparison.isNewer(latest, than: installed)
        }
        guard isNewer else { return UpdateAnswer(status: .upToDate) }
        return UpdateAnswer(
            status: .updateAvailable(
                version: latest, source: .developer, releaseNotes: item.releaseNotes,
                linkIsTheProductsPage: item.notesAreTheProductsPage ? true : nil
            ),
            notes: item.notes,
            notesPage: item.notesPage
        )
    }

    private func electronAnswer(for app: InstalledApp, installed: String, at url: URL) async -> UpdateAnswer {
        let reply = await fetchReply(url)
        guard let data = reply.data else { return Self.answer(after: reply) }
        let feed = String(decoding: data, as: UTF8.self)
        guard let latest = ElectronUpdater.version(fromFeed: feed) else { return Self.unreadable(reply) }
        guard VersionComparison.isNewer(latest, than: installed) else { return UpdateAnswer(status: .upToDate) }
        // A release the app's own updater won't offer this Mac is no update to wait for here, as the app says too.
        let updaterID = ElectronUpdater.updaterID(of: app, home: .homeDirectory)
        let release = ElectronUpdater.darwinRelease
        guard ElectronUpdater.isOffered(fromFeed: feed, darwinRelease: release, updaterID: updaterID) else {
            return UpdateAnswer(status: .upToDate)
        }
        return UpdateAnswer(
            status: .updateAvailable(version: latest, source: .developer, releaseNotes: nil),
            notes: ElectronUpdater.releaseNotes(fromFeed: feed)
        )
    }

    private func vsCodeAnswer(installed: String, at url: URL) async -> UpdateAnswer {
        let reply = await fetchReply(url)
        guard let data = reply.data else { return Self.answer(after: reply) }
        guard let latest = VSCodeUpdateService.version(in: data) else { return Self.unreadable(reply) }
        guard VersionComparison.isNewer(latest, than: installed) else { return UpdateAnswer(status: .upToDate) }
        return UpdateAnswer(status: .updateAvailable(version: latest, source: .developer, releaseNotes: nil))
    }

    /// Asks the App Store about `app`, but only when the app has an App Store receipt, whoever calls this.
    /// Asking about other apps would send Apple, one identifier at a time, the list of installed apps.
    private func appStoreAnswer(
        for app: InstalledApp, earlier: UpdateStatus?, notListedBefore: Bool
    ) async -> UpdateAnswer {
        guard app.isFromAppStore, let installed = app.version, let identifier = app.bundleIdentifier else {
            return UpdateAnswer(status: .unsupported)
        }
        let listing: AppStoreListing = if case .appStore(let listing) = app.updateFeed { listing } else { .mac }
        let store = if case .iPhoneAndiPad(_, let store?) = listing { store } else { country }
        var reply = await lookup(identifier, in: store, for: listing)
        // A two-letter region with no store, such as Antarctica (AQ), is also refused with HTTP 400.
        if reply.status == 400, store != "us" {
            reply = await lookup(identifier, in: "us", for: listing)
        }
        guard let data = reply.data else { return Self.answer(after: reply, fromTheAppStore: true) }
        switch AppStoreLookup.answer(in: data, for: listing) {
        case .unreadable:
            return UpdateAnswer(
                status: .failed, failure: UpdateFailure(asked: .appStore, cause: .unreadable(type: reply.declaredType))
            )
        case .notListed:
            // An app the store just offered an update for is believed unlisted only when the answer before this
            // one said so too; a first such answer is asked again later, as a failed check.
            if case .updateAvailable(_, .appStore, _, _) = earlier, !notListedBefore {
                return UpdateAnswer(
                    status: .failed, isNotListed: true,
                    failure: UpdateFailure(asked: .appStore, cause: .unlistedAfterAnUpdate)
                )
            }
            return UpdateAnswer(status: .unsupported, isNotListed: true)
        case .listed(let latest, let page, let developer, let notes):
            // The App Store never goes back to an older version, so an answer older than the update it gave for this
            // build comes from a copy of its catalog that isn't up to date yet, and is asked again later.
            if case .updateAvailable(let found, .appStore, _, _) = earlier,
               VersionComparison.isNewer(found, than: latest) {
                return UpdateAnswer(
                    status: .failed, developer: developer,
                    failure: UpdateFailure(asked: .appStore, cause: .olderThanFound(version: latest, found: found))
                )
            }
            guard VersionComparison.isNewer(latest, than: installed) else {
                return UpdateAnswer(status: .upToDate, developer: developer)
            }
            return UpdateAnswer(
                status: .updateAvailable(version: latest, source: .appStore, releaseNotes: page),
                developer: developer,
                notes: notes
            )
        }
    }

    /// Asks the App Store once the process's window of requests to it lets: a check that is canceled meanwhile asks
    /// nothing.
    private func lookup(_ identifier: String, in country: String, for listing: AppStoreListing) async -> Reply {
        guard let url = AppStoreLookup.url(bundleIdentifier: identifier, country: country, for: listing),
              (try? await appStoreWindow.turn()) != nil
        else { return Reply() }
        return await fetchReply(url)
    }

    /// The errors only a Mac that isn't online gets. Any other, such as a connection lost, which a server that closes
    /// it without answering gives too, means so only while this Mac has no network path.
    static func meansOffline(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }

    /// What is new in the update `answer` found, asked of the app's own addresses when the answer does not say: the
    /// notes page its feed names, or, for an update Homebrew found, the app's own feed. Nothing else is asked: a
    /// product page, a store page or a cask's homepage is a link to show, not notes to read.
    @concurrent
    public func releaseNotes(for app: InstalledApp, answer: UpdateAnswer) async -> ReleaseNotesLookup {
        guard case .updateAvailable = answer.status, let version = answer.status.displayVersion else {
            return .notGiven
        }
        if let notes = answer.notes { return .found(notes) }
        if let page = answer.notesPage { return await notes(at: page) }
        guard answer.status.source == .homebrew else { return .notGiven }
        switch app.updateFeed {
        case .sparkle(let url):
            let reply = await fetchReply(url)
            guard let data = reply.data else { return Self.lookup(withoutNotes: reply) }
            let releases = Appcast.releases(in: data, systemVersion: systemVersion, isAppleSilicon: isAppleSilicon)
            guard let item = releases?.first(where: { item in
                item.displayVersion.map { VersionComparison.compare($0, version) == .orderedSame } ?? false
            }) else { return .notGiven }
            if let notes = item.notes { return .found(notes) }
            guard let page = item.notesPage else { return .notGiven }
            return await notes(at: page)
        case .electron(let url):
            let reply = await fetchReply(url)
            guard let data = reply.data else { return Self.lookup(withoutNotes: reply) }
            let feed = String(decoding: data, as: UTF8.self)
            guard let latest = ElectronUpdater.version(fromFeed: feed),
                  VersionComparison.compare(latest, version) == .orderedSame,
                  let notes = ElectronUpdater.releaseNotes(fromFeed: feed)
            else { return .notGiven }
            return .found(notes)
        case .vsCode, .appStore, nil:
            return .notGiven
        }
    }

    /// The notes a page holds, read as Sparkle reads a release notes page: in UTF-8 unless the server names another
    /// encoding, and as Markdown, plain text or HTML by the page's type or extension.
    private func notes(at page: URL) async -> ReleaseNotesLookup {
        let reply = await fetchReply(page)
        guard let data = reply.data else { return Self.lookup(withoutNotes: reply) }
        let named = reply.textEncodingName.map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
        let encoding = named.flatMap { encoding in
            encoding == kCFStringEncodingInvalidId
                ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        }
        let text = String(data: data, encoding: encoding ?? .utf8) ?? String(decoding: data, as: UTF8.self)
        let notes = ReleaseNotes(text, format: Self.format(ofNotesAt: page, type: reply.mimeType))
        return notes.map(ReleaseNotesLookup.found) ?? .notGiven
    }

    /// A reply that brought nothing: no notes for this version when the server refused the address itself (a 4xx, but
    /// for a timeout or too many requests), and otherwise no answer, unless this Mac wasn't online.
    private static func lookup(withoutNotes reply: Reply) -> ReleaseNotesLookup {
        if reply.wasOffline { return .offline }
        guard let status = reply.status, (400..<500).contains(status), status != 408, status != 429 else {
            return .unanswered
        }
        return .notGiven
    }

    /// Markdown is asked first, since a server may send it as `text/plain`; a page with no type is HTML (Sparkle's
    /// `SUUpdateAlert`).
    static func format(ofNotesAt page: URL, type: String?) -> ReleaseNotes.Format {
        let type = type?.lowercased() ?? "text/html"
        let pathExtension = page.pathExtension.lowercased()
        if type == "text/markdown" || type == "text/x-markdown" || pathExtension == "md" || pathExtension == "markdown" {
            return .markdown
        }
        if type == "text/plain" || pathExtension == "txt" { return .plainText }
        return .html
    }

    /// A server's reply: the body when it answered 200 within the size limit, and what it said of it.
    private struct Reply {
        var data: Data?
        var status: Int?
        var mimeType: String?
        var textEncodingName: String?
        /// The type the server's `Content-Type` names, which `mimeType` guesses at when it names none.
        var declaredType: String?
        /// True when this Mac wasn't online, so no server was asked.
        var wasOffline = false
        var reachedNoServer = false
        /// The server that answered, or that couldn't be reached, by host name.
        var server: String?
        /// Why there is no body to read, when there isn't.
        var cause: UpdateFailure.Cause?

        func failure(_ cause: UpdateFailure.Cause?, fromTheAppStore: Bool) -> UpdateFailure? {
            guard let cause else { return nil }
            if fromTheAppStore { return UpdateFailure(asked: .appStore, cause: cause) }
            return server.map { UpdateFailure(asked: .server($0), cause: cause) }
        }
    }

    private static func answer(after reply: Reply, fromTheAppStore: Bool = false) -> UpdateAnswer {
        UpdateAnswer(
            status: .failed, wasOffline: reply.wasOffline, reachedNoServer: reply.reachedNoServer,
            failure: reply.failure(reply.cause, fromTheAppStore: fromTheAppStore)
        )
    }

    private static func unreadable(_ reply: Reply) -> UpdateAnswer {
        UpdateAnswer(
            status: .failed, failure: reply.failure(.unreadable(type: reply.declaredType), fromTheAppStore: false)
        )
    }

    private static func declaredType(of response: URLResponse) -> String? {
        guard let field = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") else { return nil }
        let type = field.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces).lowercased()
        return type.isEmpty ? nil : type
    }

    private static func host(of url: URL) -> String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }

    /// The address without its query and fragment, which can carry a key.
    private static func shown(_ address: URL) -> String {
        guard var parts = URLComponents(url: address, resolvingAgainstBaseURL: true) else {
            return address.absoluteString
        }
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        return parts.string ?? address.absoluteString
    }

    /// Whether this Mac has a network path at all, which a round asks once before it asks about any app.
    public func canReachTheNetwork() async -> Bool {
        await isOnline()
    }

    /// How many requests a server has answered, whatever it said, since this checker was made.
    public var serverReplies: Int { replies.count }

    private func fetchReply(_ url: URL) async -> Reply {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let delegate = SecureRedirects()
        let stream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await session.bytes(for: request, delegate: delegate)
        } catch {
            let isOffline = delegate.waitedForConnectivity || Self.meansOffline(error)
            return Reply(
                wasOffline: isOffline ? true : !(await isOnline()), reachedNoServer: true,
                server: Self.host(of: (error as? URLError)?.failingURL ?? url),
                cause: .noAnswer(error.localizedDescription)
            )
        }
        replies.add()
        let status = (response as? HTTPURLResponse)?.statusCode
        var answer = Reply(
            status: status, mimeType: response.mimeType, textEncodingName: response.textEncodingName,
            declaredType: Self.declaredType(of: response), server: Self.host(of: response.url ?? url)
        )
        if let refused = delegate.refusedAddress {
            answer.cause = .sentOnTo(Self.shown(refused))
            return answer
        }
        guard let status, status == 200 else {
            answer.cause = status.map(UpdateFailure.Cause.answered) ?? .unreadable(type: answer.declaredType)
            return answer
        }
        guard response.expectedContentLength <= Self.maximumFeedBytes else {
            answer.cause = .tooLarge
            return answer
        }

        // Reads raw bytes, giving up once the reply passes the size limit. Reading lines would be faster, but it
        // decodes UTF-8 and drops line endings, while an appcast may declare another encoding in its first line,
        // which only the raw bytes let `XMLParser` honor.
        var bytes = [UInt8]()
        bytes.reserveCapacity(min(Int(max(response.expectedContentLength, 0)), Self.maximumFeedBytes))
        do {
            for try await byte in stream {
                bytes.append(byte)
                guard bytes.count <= Self.maximumFeedBytes else {
                    answer.cause = .tooLarge
                    return answer
                }
            }
        } catch {
            answer.cause = .noAnswer(error.localizedDescription)
            return answer
        }
        answer.data = Data(bytes)
        return answer
    }
}

private final class ReplyCount: Sendable {
    private let total = Mutex(0)

    var count: Int { total.withLock { $0 } }

    func add() {
        total.withLock { $0 += 1 }
    }
}

/// Follows a redirect only to another https address. Every address an update check asks is https, while App
/// Transport Security still lets plain http reach this Mac and its local network, so a feed server could otherwise
/// send the check to a service there.
private final class SecureRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let waited = Mutex(false)
    private let refused = Mutex<URL?>(nil)

    /// True once the request waited for this Mac to go online.
    var waitedForConnectivity: Bool { waited.withLock { $0 } }
    /// The address a redirect led to that the check didn't follow. The reply is then the redirect itself.
    var refusedAddress: URL? { refused.withLock { $0 } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard request.url?.scheme == "https" else {
            refused.withLock { $0 = request.url }
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        waited.withLock { $0 = true }
    }
}

/// The result of one update check. `developer` is set only when the App Store answered.
public struct UpdateAnswer: Sendable, Hashable {
    public let status: UpdateStatus
    public let developer: String?
    /// What is new in the update found, when the answer itself says.
    public let notes: ReleaseNotes?
    /// The page the feed names for what is new in the update found, when it does not write it in.
    public let notesPage: URL?
    /// What the app's own feed or the App Store answered, `.failed` or `.unsupported`, when `status` is Homebrew's
    /// answer in its place.
    public let standsInFor: UpdateStatus?
    /// True when this Mac wasn't online, so the check learned nothing about the app.
    public let wasOffline: Bool
    /// True when the request ended before any server answered. A network that leads nowhere, such as a sign-in page, a
    /// proxy or a VPN, looks like this for every feed at once, so it says something of a feed only if another answers.
    public let reachedNoServer: Bool
    /// True when the App Store answered that it lists no such app.
    public let isNotListed: Bool
    /// Why the app's own source gave no answer, when it failed.
    public let failure: UpdateFailure?

    public init(
        status: UpdateStatus,
        developer: String? = nil,
        notes: ReleaseNotes? = nil,
        notesPage: URL? = nil,
        standsInFor: UpdateStatus? = nil,
        wasOffline: Bool = false,
        reachedNoServer: Bool = false,
        isNotListed: Bool = false,
        failure: UpdateFailure? = nil
    ) {
        self.status = status
        self.developer = developer
        self.notes = notes
        self.notesPage = notesPage
        self.standsInFor = standsInFor
        self.wasOffline = wasOffline
        self.reachedNoServer = reachedNoServer
        self.isNotListed = isNotListed
        self.failure = failure
    }

    /// The status to keep after `previous`: a check whose own source failed keeps an update that source found earlier,
    /// even where Homebrew answered in its place, and an update Homebrew reported is kept only while Homebrew gives it.
    public func following(_ previous: UpdateStatus?) -> UpdateStatus {
        if (standsInFor ?? status) == .failed, let previous, case .updateAvailable(_, let source, _, _) = previous,
           source != .homebrew {
            return previous
        }
        return status
    }
}

/// Why Peel can't check an app for updates, which the note behind Can't check for updates says in words.
public enum CannotCheck: Sendable, Hashable {
    case homebrewCannotTell(HomebrewCannotTell)
    /// It came with macOS, which Software Update keeps current.
    case cameWithMacOS
    /// It came from Setapp, which keeps it current.
    case cameFromSetapp
    case namesNoVersion
    /// The App Store gave no version to compare: it doesn't sell the app in `store`, the country of the store an
    /// iPhone or iPad app came from, or, when nil, in this Mac's region.
    case notInTheAppStore(store: String?)
    case namesNoFeed
}

/// Why Homebrew, which installed an app nobody else can answer for, can't say whether the app is up to date.
public struct HomebrewCannotTell: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        /// Homebrew last checked for new versions over a day ago, or when isn't known.
        case notCheckedRecently
        /// The cask installs whatever is newest each time (`version :latest`), so there is no version to compare.
        case installsTheNewest
        /// The app updates itself, and Homebrew's settings leave such casks to their apps
        /// (`HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS`).
        case leftToTheApp
        /// Homebrew has disabled the cask, so it no longer upgrades it.
        case disabled
    }

    public let cask: HomebrewPackage
    public let reason: Reason
}

/// What asking for an update's notes came to.
public enum ReleaseNotesLookup: Sendable, Hashable {
    case found(ReleaseNotes)
    /// None are given for this version, or there is no address of the app's own to ask: not asked again.
    case notGiven
    /// The server did not answer, so they are asked for again once a wait is over.
    case unanswered
    /// This Mac wasn't online, so no server was asked and nothing was learned.
    case offline
}
