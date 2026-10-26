public import Foundation
import Synchronization

public struct UpdateChecker: Sendable {
    /// Raised whenever the checker answers some apps differently: an app an earlier revision couldn't check is asked
    /// again rather than waited out, and so is one this revision asks nobody about (`UpdateMemory.recalled`).
    public static let revision = 3

    /// The largest reply read. An update feed is a small XML, YAML, or JSON file, and its address comes from
    /// the app's own bundle, so the server is not trusted to keep its reply small.
    private static let maximumFeedBytes = 4 * 1_024 * 1_024

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

    public init(
        session: URLSession? = nil, locale: Locale = .current, clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.init(session: session, locale: locale, clock: clock, appStoreWindow: .appStore)
    }

    init(
        session: URLSession? = nil, locale: Locale = .current, clock: @escaping @Sendable () -> Date = { .now },
        appStoreWindow: RequestWindow
    ) {
        self.session = session ?? URLSession(configuration: Self.configuration)
        self.appStoreWindow = appStoreWindow
        self.clock = clock
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
    /// believe when an app can be updated in more than one way, and `earlier` is the last answer about this build.
    @concurrent
    public func status(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = [],
        earlier: UpdateStatus? = nil
    ) async -> UpdateStatus {
        await answer(for: app, preference: preference, casks: casks, earlier: earlier).status
    }

    /// Returns the update status, and the developer's name when the App Store answered. An App Store app is
    /// signed by Apple, so its signature does not name the developer, but the store's record does.
    @concurrent
    public func answer(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = [],
        earlier: UpdateStatus? = nil
    ) async -> UpdateAnswer {
        let homebrew = homebrewStatus(for: app, casks: casks)
        if let status = Self.statusWithoutAsking(for: app, preference: preference, homebrew: homebrew) {
            return UpdateAnswer(status: status)
        }
        // Even with the App Store preferred, Apple is asked only about apps from the App Store. Any other app is
        // checked through its own feed, or not at all.
        let own = preference == .appStore && app.isFromAppStore
            ? await appStoreAnswer(for: app, earlier: earlier) : await feedAnswer(for: app, earlier: earlier)
        guard !own.wasOffline else { return own }
        // A feed can be down, and the App Store may not sell the app here: what Homebrew knows is used then.
        if let homebrew, own.status == .unsupported || own.status == .failed {
            return UpdateAnswer(status: homebrew, developer: own.developer, standsInFor: own.status)
        }
        return own
    }

    /// The status `answer` gives `app` without asking a server, from Homebrew's casks and the app's own files, or nil
    /// when its source must be asked. Where that source had no answer (`known`), Homebrew's counts, else `known`.
    public func statusWithoutAsking(
        for app: InstalledApp, preference: UpdateSource, casks: [HomebrewPackage], known: UpdateStatus? = nil
    ) -> UpdateStatus? {
        let homebrew = homebrewStatus(for: app, casks: casks)
        if let status = Self.statusWithoutAsking(for: app, preference: preference, homebrew: homebrew) {
            return status
        }
        return known == .unsupported || known == .failed ? homebrew ?? known : nil
    }

    private static func statusWithoutAsking(
        for app: InstalledApp, preference: UpdateSource, homebrew: UpdateStatus?
    ) -> UpdateStatus? {
        let asksNobody = asksNobody(about: app, preference: preference)
        switch preference {
        case .homebrew:
            // A cask Homebrew knows but never installed says nothing about this app's version, and neither does one
            // Homebrew can't tell about, so the app's own feed answers then instead of a false "up to date".
            return homebrew ?? (asksNobody ? .unsupported : nil)
        case .automatic, .developer, .appStore:
            if preference == .automatic, case .updateAvailable = homebrew { return homebrew }
            // An app from a cask may have no feed of its own: what Homebrew knows is used rather than "Can't check
            // for updates".
            return asksNobody ? homebrew ?? .unsupported : nil
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

    /// Homebrew's answer for `app`, found without a network request, or nil when Homebrew did not install this copy
    /// or can't tell (`homebrewStatus(of:appVersion:at:)`). For a cask it did not install, Homebrew has a definition
    /// but no installed version to compare.
    public func homebrewStatus(for app: InstalledApp, casks: [HomebrewPackage]) -> UpdateStatus? {
        CaskEvidence.installedCask(for: app, in: casks).flatMap {
            Self.homebrewStatus(of: $0, appVersion: app.version, at: clock())
        }
    }

    /// The status Homebrew reports at `now` for `cask`, known to be the app's at `appVersion`, or nil when it can't
    /// tell: a cask not outdated is up to date only within `Homebrew.autoUpdateInterval` of Homebrew's last check for
    /// new versions.
    static func homebrewStatus(of cask: HomebrewPackage, appVersion: String?, at now: Date) -> UpdateStatus? {
        if cask.isOutdated, let latest = cask.latestVersion, !isAlready(appVersion, at: latest) {
            return .updateAvailable(version: latest, source: .homebrew, releaseNotes: cask.homepage)
        }
        guard let checked = cask.lastUpdateCheck, now.timeIntervalSince(checked) < Homebrew.autoUpdateInterval else {
            return nil
        }
        return .upToDate
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

    /// The cask `app` came from when only Homebrew could say whether it is up to date and Homebrew's last check for
    /// new versions is too old to tell (`homebrewStatus(of:appVersion:at:)`), so a check has no answer for it.
    public func caskNotCheckedRecently(
        for app: InstalledApp, preference: UpdateSource, casks: [HomebrewPackage]
    ) -> HomebrewPackage? {
        guard Self.asksNobody(about: app, preference: preference),
              let cask = CaskEvidence.installedCask(for: app, in: casks)
        else { return nil }
        return Self.homebrewStatus(of: cask, appVersion: app.version, at: clock()) == nil ? cask : nil
    }

    private func feedAnswer(for app: InstalledApp, earlier: UpdateStatus?) async -> UpdateAnswer {
        // An app whose bundle names no version has nothing to compare a release with, so nobody is asked.
        guard let installed = app.version else { return UpdateAnswer(status: .unsupported) }
        return switch app.updateFeed {
        case nil: UpdateAnswer(status: .unsupported)
        case .sparkle(let url): await sparkleAnswer(for: app, installed: installed, at: url)
        case .electron(let url): await electronAnswer(installed: installed, at: url)
        case .appStore: await appStoreAnswer(for: app, earlier: earlier)
        }
    }

    private func sparkleAnswer(for app: InstalledApp, installed: String, at url: URL) async -> UpdateAnswer {
        let reply = await fetchReply(url)
        guard let data = reply.data else { return UpdateAnswer(status: .failed, wasOffline: reply.wasOffline) }
        let item: AppcastItem
        switch Appcast.read(data, systemVersion: systemVersion, isAppleSilicon: isAppleSilicon) {
        case .unreadable: return UpdateAnswer(status: .failed)
        case .nothingForThisMac: return UpdateAnswer(status: .upToDate)
        case .latest(let latest): item = latest
        }
        guard let latest = item.displayVersion else { return UpdateAnswer(status: .failed) }
        let isNewer = if let version = item.version, let build = app.buildVersion {
            VersionComparison.isNewer(version, than: build)
        } else {
            VersionComparison.isNewer(latest, than: installed)
        }
        guard isNewer else { return UpdateAnswer(status: .upToDate) }
        return UpdateAnswer(
            status: .updateAvailable(version: latest, source: .developer, releaseNotes: item.releaseNotes),
            notes: item.notes,
            notesPage: item.notesPage
        )
    }

    private func electronAnswer(installed: String, at url: URL) async -> UpdateAnswer {
        let reply = await fetchReply(url)
        guard let data = reply.data else { return UpdateAnswer(status: .failed, wasOffline: reply.wasOffline) }
        let feed = String(decoding: data, as: UTF8.self)
        guard let latest = ElectronUpdater.version(fromFeed: feed) else { return UpdateAnswer(status: .failed) }
        guard VersionComparison.isNewer(latest, than: installed) else { return UpdateAnswer(status: .upToDate) }
        return UpdateAnswer(
            status: .updateAvailable(version: latest, source: .developer, releaseNotes: nil),
            notes: ElectronUpdater.releaseNotes(fromFeed: feed)
        )
    }

    /// Asks the App Store about `app`, but only when the app has an App Store receipt, whoever calls this.
    /// Asking about other apps would send Apple, one identifier at a time, the list of installed apps.
    private func appStoreAnswer(for app: InstalledApp, earlier: UpdateStatus?) async -> UpdateAnswer {
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
        guard let data = reply.data else { return UpdateAnswer(status: .failed, wasOffline: reply.wasOffline) }
        switch AppStoreLookup.answer(in: data, for: listing) {
        case .unreadable:
            return UpdateAnswer(status: .failed)
        case .notListed:
            return UpdateAnswer(status: .unsupported)
        case .listed(let latest, let page, let developer, let notes):
            // The App Store never goes back to an older version, so an answer older than the update it gave for this
            // build comes from a copy of its catalog that isn't up to date yet, and is asked again later.
            if case .updateAvailable(let found, .appStore, _) = earlier,
               VersionComparison.isNewer(found, than: latest) {
                return UpdateAnswer(status: .failed, developer: developer)
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

    private func fetch(_ url: URL) async -> Data? {
        await fetchReply(url).data
    }

    /// The errors that mean this Mac isn't online rather than that the server failed.
    static func meansOffline(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff]
            .contains(error.code)
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
            guard let data = await fetch(url) else { return .unanswered }
            let releases = Appcast.releases(in: data, systemVersion: systemVersion, isAppleSilicon: isAppleSilicon)
            guard let item = releases?.first(where: { item in
                item.displayVersion.map { VersionComparison.compare($0, version) == .orderedSame } ?? false
            }) else { return .notGiven }
            if let notes = item.notes { return .found(notes) }
            guard let page = item.notesPage else { return .notGiven }
            return await notes(at: page)
        case .electron(let url):
            guard let data = await fetch(url) else { return .unanswered }
            let feed = String(decoding: data, as: UTF8.self)
            guard let latest = ElectronUpdater.version(fromFeed: feed),
                  VersionComparison.compare(latest, version) == .orderedSame,
                  let notes = ElectronUpdater.releaseNotes(fromFeed: feed)
            else { return .notGiven }
            return .found(notes)
        case .appStore, nil:
            return .notGiven
        }
    }

    /// The notes a page holds, read as Sparkle reads a release notes page: in UTF-8 unless the server names another
    /// encoding, and as Markdown, plain text or HTML by the page's type or extension.
    private func notes(at page: URL) async -> ReleaseNotesLookup {
        let reply = await fetchReply(page)
        guard let data = reply.data else { return .unanswered }
        let named = reply.textEncodingName.map { CFStringConvertIANACharSetNameToEncoding($0 as CFString) }
        let encoding = named.flatMap { encoding in
            encoding == kCFStringEncodingInvalidId
                ? nil : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
        }
        let text = String(data: data, encoding: encoding ?? .utf8) ?? String(decoding: data, as: UTF8.self)
        let notes = ReleaseNotes(text, format: Self.format(ofNotesAt: page, type: reply.mimeType))
        return notes.map(ReleaseNotesLookup.found) ?? .notGiven
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
        /// True when this Mac wasn't online, so no server was asked.
        var wasOffline = false
    }

    private func fetchReply(_ url: URL) async -> Reply {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let delegate = SecureRedirects()
        let stream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await session.bytes(for: request, delegate: delegate)
        } catch {
            return Reply(wasOffline: delegate.waitedForConnectivity || Self.meansOffline(error))
        }
        let status = (response as? HTTPURLResponse)?.statusCode
        var answer = Reply(status: status, mimeType: response.mimeType, textEncodingName: response.textEncodingName)
        guard status == 200, response.expectedContentLength <= Self.maximumFeedBytes else { return answer }

        // Reads raw bytes, giving up once the reply passes the size limit. Reading lines would be faster, but it
        // decodes UTF-8 and drops line endings, while an appcast may declare another encoding in its first line,
        // which only the raw bytes let `XMLParser` honor.
        var bytes = [UInt8]()
        bytes.reserveCapacity(min(Int(max(response.expectedContentLength, 0)), Self.maximumFeedBytes))
        do {
            for try await byte in stream {
                bytes.append(byte)
                guard bytes.count <= Self.maximumFeedBytes else { return answer }
            }
        } catch {
            return answer
        }
        answer.data = Data(bytes)
        return answer
    }
}

/// Follows a redirect only to another https address. Every address an update check asks is https, while App
/// Transport Security still lets plain http reach this Mac and its local network, so a feed server could otherwise
/// send the check to a service there.
private final class SecureRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let waited = Mutex(false)

    /// True once the request waited for this Mac to go online.
    var waitedForConnectivity: Bool { waited.withLock { $0 } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
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

    public init(
        status: UpdateStatus,
        developer: String? = nil,
        notes: ReleaseNotes? = nil,
        notesPage: URL? = nil,
        standsInFor: UpdateStatus? = nil,
        wasOffline: Bool = false
    ) {
        self.status = status
        self.developer = developer
        self.notes = notes
        self.notesPage = notesPage
        self.standsInFor = standsInFor
        self.wasOffline = wasOffline
    }

    /// The status to keep after `previous`: a check whose own source failed keeps an update that source found earlier,
    /// even where Homebrew answered in its place, and an update Homebrew reported is kept only while Homebrew gives it.
    public func following(_ previous: UpdateStatus?) -> UpdateStatus {
        if (standsInFor ?? status) == .failed, let previous, case .updateAvailable(_, let source, _) = previous,
           source != .homebrew {
            return previous
        }
        return status
    }
}

/// What asking for an update's notes came to.
public enum ReleaseNotesLookup: Sendable, Hashable {
    case found(ReleaseNotes)
    /// None are given for this version, or there is no address of the app's own to ask: not asked again.
    case notGiven
    /// The server did not answer, so they are asked for again with the next check.
    case unanswered
}
