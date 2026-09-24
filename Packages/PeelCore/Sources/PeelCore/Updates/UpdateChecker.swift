public import Foundation

public struct UpdateChecker: Sendable {
    /// The largest reply read. An update feed is a small XML, YAML, or JSON file, and its address comes from
    /// the app's own bundle, so the server is not trusted to keep its reply small.
    private static let maximumFeedBytes = 4 * 1_024 * 1_024

    /// Settings for Peel's own session, used instead of the shared one: no cookies, no cache, and time limits.
    /// A feed server should not set a cookie, read one left by another app's check, or hold a connection open.
    private static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private let session: URLSession
    private let country: String
    private let systemVersion: String

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
    public func status(for app: InstalledApp, preference: UpdateSource = .automatic, casks: [HomebrewPackage] = []) async -> UpdateStatus {
        await answer(for: app, preference: preference, casks: casks).status
    }

    /// Returns the update status, and the developer's name when the App Store answered. An App Store app is
    /// signed by Apple, so its signature does not name the developer, but the store's record does.
    @concurrent
    public func answer(for app: InstalledApp, preference: UpdateSource = .automatic, casks: [HomebrewPackage] = []) async -> UpdateAnswer {
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
            if let homebrew, feed.status == .unsupported || feed.status == .failed { return UpdateAnswer(status: homebrew, developer: feed.developer) }
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
        switch app.updateFeed {
        case nil: UpdateAnswer(status: .unsupported)
        case .sparkle(let url): UpdateAnswer(status: await sparkleStatus(for: app, at: url))
        case .electron(let url): UpdateAnswer(status: await electronStatus(for: app, at: url))
        case .appStore: await appStoreAnswer(for: app)
        }
    }

    private func sparkleStatus(for app: InstalledApp, at url: URL) async -> UpdateStatus {
        guard let data = await fetch(url) else { return .failed }
        let item: AppcastItem
        switch Appcast.read(data, systemVersion: systemVersion) {
        case .unreadable: return .failed
        case .nothingForThisMac: return .upToDate
        case .latest(let latest): item = latest
        }
        guard let latest = item.displayVersion else { return .failed }
        let isNewer = if let version = item.version, let build = app.buildVersion {
            VersionComparison.isNewer(version, than: build)
        } else {
            VersionComparison.isNewer(latest, than: app.version ?? "")
        }
        return isNewer ? .updateAvailable(version: latest, source: .developer, releaseNotes: item.releaseNotes) : .upToDate
    }

    private func electronStatus(for app: InstalledApp, at url: URL) async -> UpdateStatus {
        guard
            let data = await fetch(url),
            let latest = ElectronUpdater.version(fromFeed: String(decoding: data, as: UTF8.self))
        else { return .failed }
        return VersionComparison.isNewer(latest, than: app.version ?? "")
            ? .updateAvailable(version: latest, source: .developer, releaseNotes: nil)
            : .upToDate
    }

    /// Asks the App Store about `app`, but only when the app has an App Store receipt, whoever calls this.
    /// Asking about other apps would send Apple, one identifier at a time, the list of installed apps.
    private func appStoreAnswer(for app: InstalledApp) async -> UpdateAnswer {
        guard app.isFromAppStore else { return UpdateAnswer(status: .unsupported) }
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
        case .mac(let latest, let page, let developer):
            let status: UpdateStatus = VersionComparison.isNewer(latest, than: app.version ?? "")
                ? .updateAvailable(version: latest, source: .appStore, releaseNotes: page)
                : .upToDate
            return UpdateAnswer(status: status, developer: developer)
        }
    }

    private func lookup(_ identifier: String, in country: String) async -> (data: Data?, status: Int?) {
        guard let url = AppStoreLookup.url(bundleIdentifier: identifier, country: country) else { return (nil, nil) }
        return await fetchReply(url)
    }

    private func fetch(_ url: URL) async -> Data? {
        await fetchReply(url).data
    }

    private func fetchReply(_ url: URL) async -> (data: Data?, status: Int?) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        guard let (stream, response) = try? await session.bytes(for: request) else { return (nil, nil) }
        let status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200, response.expectedContentLength <= Self.maximumFeedBytes else { return (nil, status) }

        // Reads raw bytes, giving up once the reply passes the size limit. Reading lines would be faster, but it
        // decodes UTF-8 and drops line endings, while an appcast may declare another encoding in its first line,
        // which only the raw bytes let `XMLParser` honor.
        var bytes = [UInt8]()
        bytes.reserveCapacity(min(Int(max(response.expectedContentLength, 0)), Self.maximumFeedBytes))
        do {
            for try await byte in stream {
                bytes.append(byte)
                guard bytes.count <= Self.maximumFeedBytes else { return (nil, status) }
            }
        } catch {
            return (nil, status)
        }
        return (Data(bytes), status)
    }
}

/// The result of one update check. `developer` is set only when the App Store answered.
public struct UpdateAnswer: Sendable, Hashable {
    public let status: UpdateStatus
    public let developer: String?

    public init(status: UpdateStatus, developer: String? = nil) {
        self.status = status
        self.developer = developer
    }
}
