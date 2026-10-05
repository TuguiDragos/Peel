public import Foundation

public struct UpdateChecker: Sendable {
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
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "Peel", "Accept-Language": "*"]
        return configuration
    }

    private let session: URLSession
    private let country: String
    private let systemVersion: String
    private let isAppleSilicon = HostArchitecture.isAppleSilicon

    public init(session: URLSession? = nil, locale: Locale = .current) {
        self.session = session ?? URLSession(configuration: Self.configuration)
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
    /// believe when an app can be updated in more than one way.
    @concurrent
    public func status(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = []
    ) async -> UpdateStatus {
        await answer(for: app, preference: preference, casks: casks).status
    }

    /// Returns the update status, and the developer's name when the App Store answered. An App Store app is
    /// signed by Apple, so its signature does not name the developer, but the store's record does.
    @concurrent
    public func answer(
        for app: InstalledApp,
        preference: UpdateSource = .automatic,
        casks: [HomebrewPackage] = []
    ) async -> UpdateAnswer {
        switch preference {
        case .homebrew:
            // A cask Homebrew knows but never installed says nothing about this app's version, so the
            // app's own feed answers instead of a false "up to date".
            if let homebrew = homebrewStatus(for: app, casks: casks) { return UpdateAnswer(status: homebrew) }
            return await feedAnswer(for: app)
        case .appStore:
            // Even with this preference, Apple is asked only about apps from the App Store. Any other app is
            // checked through its own feed, or not at all.
            return app.isFromAppStore ? await appStoreAnswer(for: app) : await feedAnswer(for: app)
        case .developer:
            return await feedAnswer(for: app)
        case .automatic:
            let homebrew = homebrewStatus(for: app, casks: casks)
            if case .updateAvailable = homebrew { return UpdateAnswer(status: homebrew ?? .unsupported) }
            // An app from a cask may have no feed of its own, and a feed can be down. In both cases what Homebrew
            // knows is used rather than "Can't check for updates".
            let feed = await feedAnswer(for: app)
            if let homebrew, feed.status == .unsupported || feed.status == .failed {
                return UpdateAnswer(status: homebrew, developer: feed.developer)
            }
            return feed
        }
    }

    /// Homebrew's answer for `app`, found without a network request, or nil when Homebrew did not install this
    /// copy. For a cask it did not install, Homebrew has a definition but no installed version to compare.
    public func homebrewStatus(for app: InstalledApp, casks: [HomebrewPackage]) -> UpdateStatus? {
        CaskEvidence.installedCask(for: app, in: casks).map(Self.homebrewStatus(of:))
    }

    /// The status Homebrew reports for `cask`, which is already known to be the app's.
    public static func homebrewStatus(of cask: HomebrewPackage) -> UpdateStatus {
        guard cask.isOutdated, let latest = cask.latestVersion else { return .upToDate }
        return .updateAvailable(version: latest, source: .homebrew, releaseNotes: cask.homepage)
    }

    private func feedAnswer(for app: InstalledApp) async -> UpdateAnswer {
        // An app whose bundle names no version has nothing to compare a release with, so nobody is asked.
        guard let installed = app.version else { return UpdateAnswer(status: .unsupported) }
        return switch app.updateFeed {
        case nil: UpdateAnswer(status: .unsupported)
        case .sparkle(let url): await sparkleAnswer(for: app, installed: installed, at: url)
        case .electron(let url): await electronAnswer(installed: installed, at: url)
        case .gitHubRelease(let url): await gitHubReleaseAnswer(installed: installed, at: url)
        case .appStore: await appStoreAnswer(for: app)
        }
    }

    private func sparkleAnswer(for app: InstalledApp, installed: String, at url: URL) async -> UpdateAnswer {
        guard let data = await fetch(url) else { return UpdateAnswer(status: .failed) }
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
        guard let data = await fetch(url) else { return UpdateAnswer(status: .failed) }
        let feed = String(decoding: data, as: UTF8.self)
        guard let latest = ElectronUpdater.version(fromFeed: feed) else { return UpdateAnswer(status: .failed) }
        guard VersionComparison.isNewer(latest, than: installed) else { return UpdateAnswer(status: .upToDate) }
        return UpdateAnswer(
            status: .updateAvailable(version: latest, source: .developer, releaseNotes: nil),
            notes: ElectronUpdater.releaseNotes(fromFeed: feed)
        )
    }

    private func gitHubReleaseAnswer(installed: String, at url: URL) async -> UpdateAnswer {
        guard let data = await fetch(url), let release = GitHubRelease.latest(in: data) else {
            return UpdateAnswer(status: .failed)
        }
        guard VersionComparison.isNewer(release.version, than: installed) else {
            return UpdateAnswer(status: .upToDate)
        }
        return UpdateAnswer(
            status: .updateAvailable(version: release.version, source: .developer, releaseNotes: release.page),
            notes: release.notes
        )
    }

    /// Asks the App Store about `app`, but only when the app has an App Store receipt, whoever calls this.
    /// Asking about other apps would send Apple, one identifier at a time, the list of installed apps.
    private func appStoreAnswer(for app: InstalledApp) async -> UpdateAnswer {
        guard app.isFromAppStore, let installed = app.version else { return UpdateAnswer(status: .unsupported) }
        var reply = await lookup(app.bundleIdentifier, in: country)
        // A two-letter region with no store, such as Antarctica (AQ), is also refused with HTTP 400.
        if reply.status == 400, country != "us" {
            reply = await lookup(app.bundleIdentifier, in: "us")
        }
        guard let data = reply.data else { return UpdateAnswer(status: .failed) }
        switch AppStoreLookup.answer(in: data) {
        case .unreadable:
            return UpdateAnswer(status: .failed)
        case .noMacRecord:
            return UpdateAnswer(status: .unsupported)
        case .mac(let latest, let page, let developer, let notes):
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

    private func lookup(_ identifier: String, in country: String) async -> Reply {
        guard let url = AppStoreLookup.url(bundleIdentifier: identifier, country: country) else { return Reply() }
        return await fetchReply(url)
    }

    private func fetch(_ url: URL) async -> Data? {
        await fetchReply(url).data
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
        case .gitHubRelease, .appStore, nil:
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
    }

    private func fetchReply(_ url: URL) async -> Reply {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let reply = try? await session.bytes(for: request, delegate: SecureRedirects())
        guard let (stream, response) = reply else { return Reply() }
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
private final class SecureRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
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

    public init(status: UpdateStatus, developer: String? = nil, notes: ReleaseNotes? = nil, notesPage: URL? = nil) {
        self.status = status
        self.developer = developer
        self.notes = notes
        self.notesPage = notesPage
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
