public import Foundation
internal import PeelPrivileged

public enum UpdateFeed: Sendable, Hashable {
    case sparkle(URL)
    case electron(URL)
    case appStore
}

public enum UpdateSource: String, Sendable, Hashable, CaseIterable, Codable {
    case automatic
    case appStore
    case developer
    case homebrew
}

/// The answer to an update check. It is `Codable` so answers survive a relaunch: apps are checked on a
/// schedule, and a lost answer would leave an app with no status until its next check.
public enum UpdateStatus: Sendable, Hashable, Codable {
    case updateAvailable(version: String, source: UpdateSource = .developer, releaseNotes: URL? = nil)
    case upToDate
    case unsupported
    case failed

    public var version: String? {
        if case .updateAvailable(let version, _, _) = self { version } else { nil }
    }

    /// The version to show the user. Homebrew adds what the download needs after a comma in a cask's version
    /// (`26.10.22,802`), so only the part before the comma is shown. The full string is what is compared and
    /// skipped.
    public var displayVersion: String? {
        guard case .updateAvailable(let version, let source, _) = self else { return nil }
        return source == .homebrew ? String(version.prefix { $0 != "," }) : version
    }

    /// The status to keep when this answer follows `previous`. A failed check keeps an update found earlier,
    /// since failing to reach the server says nothing about that update.
    public func following(_ previous: UpdateStatus?) -> UpdateStatus {
        if self == .failed, case .updateAvailable = previous { return previous ?? self }
        return self
    }

    public var releaseNotes: URL? {
        if case .updateAvailable(_, _, let notes) = self { notes } else { nil }
    }

    public var source: UpdateSource? {
        if case .updateAvailable(_, let source, _) = self { source } else { nil }
    }

    /// Whether this answer still holds for an app, given whether Homebrew counts the app as its own now: an update
    /// Homebrew reported is about its cask, and says nothing once the app is not Homebrew's.
    public func holds(whileHomebrews isHomebrews: Bool) -> Bool {
        source != .homebrew || isHomebrews
    }
}

extension UpdateFeed {
    static func detect(
        info: [String: Any],
        contents: URL,
        isFromAppStore: Bool,
        isSystemProtected: Bool
    ) -> UpdateFeed? {
        guard !isSystemProtected else { return nil }
        if isFromAppStore {
            return .appStore
        }
        if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme == "https" {
            return .sparkle(feed)
        }
        let configuration = contents.appending(path: "Resources/app-update.yml")
        // The app's own file, read for every bundle on every refresh. A real one is a few lines, so anything
        // over 64 KB, or anything that is not a regular file, is ignored.
        if let data = BoundedRead.data(at: configuration, maximum: 64 * 1_024),
           let feed = ElectronUpdater.feedURL(fromConfiguration: String(decoding: data, as: UTF8.self)) {
            return .electron(feed)
        }
        // An app that names no update source gets no feed. Asking Apple about it would send its identifier
        // to itunes.apple.com, and doing that for every app would send Apple the list of installed apps, which
        // update checks never do.
        return nil
    }
}
