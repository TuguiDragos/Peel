public import Foundation
internal import PeelPrivileged

public enum UpdateFeed: Sendable, Hashable {
    case sparkle(URL)
    case electron(URL)
    case appStore(AppStoreListing)
}

/// The App Store listing that describes an app's bundle, and so the one its updates are read from.
public enum AppStoreListing: Sendable, Hashable {
    case mac
    /// An iPhone or iPad app installed on a Mac, whose bundle is the very build that listing sells, with the
    /// listing's number and the country of its store as the App Store's metadata beside the app gives them.
    case iPhoneAndiPad(item: Int?, store: String?)
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

    public var releaseNotes: URL? {
        if case .updateAvailable(_, _, let notes) = self { notes } else { nil }
    }

    public var source: UpdateSource? {
        if case .updateAvailable(_, let source, _) = self { source } else { nil }
    }

    /// Whether this answer still holds for an app, given what Homebrew says of the app now, nil where the app isn't
    /// Homebrew's or Homebrew says nothing that counts: an update Homebrew reported holds only while Homebrew reports
    /// one.
    public func holds(whileHomebrewSays homebrew: UpdateStatus?) -> Bool {
        guard source == .homebrew else { return true }
        if case .updateAvailable = homebrew { return true }
        return false
    }
}

extension UpdateFeed {
    static func detect(
        info: [String: Any],
        electronConfiguration: String?,
        appStoreListing: AppStoreListing?,
        isSystemProtected: Bool,
        isFromSetapp: Bool
    ) -> UpdateFeed? {
        // Software Update keeps macOS's own apps current and Setapp the apps it installed, whatever feed the bundle
        // names: Setapp's build of an app may still carry the feed of the version sold directly.
        guard !isSystemProtected, !isFromSetapp else { return nil }
        if let appStoreListing {
            return .appStore(appStoreListing)
        }
        if let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), feed.scheme == "https" {
            return .sparkle(feed)
        }
        if let feed = electronConfiguration.flatMap(ElectronUpdater.feedURL(fromConfiguration:)) {
            return .electron(feed)
        }
        // An app that names no update source gets no feed. Asking Apple about it would send its identifier
        // to itunes.apple.com, and doing that for every app would send Apple the list of installed apps, which
        // update checks never do.
        return nil
    }
}
