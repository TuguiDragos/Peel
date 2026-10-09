/// Where an app came from, as the Applications list's filter tells them apart.
public enum AppSource: String, CaseIterable, Identifiable, Sendable {
    case appStore
    case homebrew
    case setapp
    case direct

    public var id: String { rawValue }

    public static func of(_ app: InstalledApp, installedByHomebrew: Bool) -> AppSource {
        if app.isFromAppStore { return .appStore }
        if app.isFromSetapp { return .setapp }
        return installedByHomebrew ? .homebrew : .direct
    }
}

/// What the Applications list keeps of the installed apps: what a search finds by name, identifier or developer,
/// narrowed by each filter that is on.
public struct AppListFilter: Sendable, Hashable {
    public var text = ""
    public var sources: Set<AppSource> = []
    public var developer: String?
    public var onlyUnused = false

    public init(text: String = "", sources: Set<AppSource> = [], developer: String? = nil, onlyUnused: Bool = false) {
        self.text = text
        self.sources = sources
        self.developer = developer
        self.onlyUnused = onlyUnused
    }

    public func keeps(
        _ app: InstalledApp, source: AppSource, developer appsDeveloper: String?, isUnused: Bool
    ) -> Bool {
        if !text.isEmpty, !SearchText.matches(app.name, text),
           !(app.bundleIdentifier.map { SearchText.matches($0, text) } ?? false),
           !(appsDeveloper.map { SearchText.matches($0, text) } ?? false) {
            return false
        }
        if !sources.isEmpty, !sources.contains(source) { return false }
        if let developer, appsDeveloper != developer { return false }
        return !onlyUnused || isUnused
    }
}
