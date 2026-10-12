/// How an app Peel lists, but never removes from its page, is removed instead. Nothing of it is selected, counted,
/// moved, or handed to the helper.
public enum RemovedElsewhere: Sendable, Hashable {
    /// Peel itself: Remove Peel, in Settings, also takes its helper and login item away.
    case byRemovePeel
    /// A security or management agent, which its maker's own uninstaller removes whole.
    case byItsMaker(MakersUninstaller)
    /// An app with system extensions macOS installed, which Finder's move asks macOS to remove and Peel's would not.
    case byFinder(systemExtensions: CarriedSystemExtensions)

    public static func of(
        _ app: InstalledApp,
        installedSystemExtensions carried: CarriedSystemExtensions
    ) -> RemovedElsewhere? {
        app.removedElsewhere ?? (carried.isEmpty ? nil : .byFinder(systemExtensions: carried))
    }

    /// How the first of `apps` that Peel never removes is removed instead, such as one of the apps a cask installed.
    public static func first(
        among apps: [InstalledApp],
        asking answer: @escaping AppExtensions.SystemExtensionsAnswer = AppExtensions.askingMacOS
    ) async -> RemovedElsewhere? {
        for app in apps {
            let carried = await AppExtensions.installed(carriedBy: app, asking: answer)
            if let found = of(app, installedSystemExtensions: carried) { return found }
        }
        return nil
    }
}
