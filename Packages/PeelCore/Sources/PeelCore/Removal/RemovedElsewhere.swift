/// How an app Peel lists, but never removes from its page, is removed instead. Nothing of it is selected, counted,
/// moved, or handed to the helper.
public enum RemovedElsewhere: Sendable, Hashable {
    /// Peel itself: Remove Peel, in Settings, also takes its helper and login item away.
    case byRemovePeel
    /// A security or management agent, which its maker's own uninstaller removes whole.
    case byItsMaker(MakersUninstaller)
    /// An app carrying system extensions macOS installed: only its move to the Trash in Finder makes macOS remove them.
    case byFinder(systemExtensions: [String])

    public static func of(_ app: InstalledApp, installedSystemExtensions names: [String]) -> RemovedElsewhere? {
        app.removedElsewhere ?? (names.isEmpty ? nil : .byFinder(systemExtensions: names))
    }
}
