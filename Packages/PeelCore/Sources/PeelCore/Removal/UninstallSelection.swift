public import Foundation

/// What is selected on an app's page, or on several apps' page, kept across its scans (`KeptSelection`) and as the
/// helper comes and goes.
///
/// When an app comes to stay, what it holds was chosen for it going, so none of it stays selected: its files would
/// go and leave it without them. When it can go again, Peel's suggestion comes back for it only if the person left
/// the selection as Peel made it.
public struct UninstallSelection: Sendable {
    private var kept = KeptSelection()
    /// Whether each app stayed at the last update, by bundle identifier.
    private var stayed: [String: Bool] = [:]
    /// What a checkbox can select as of the last update.
    public private(set) var selectable: Set<URL> = []

    public init() {}

    public mutating func update(_ selected: Set<URL>, in uninstallation: Uninstallation, canUseHelper: Bool) -> Set<URL> {
        let holds = Set(uninstallation.scan.leftovers.map(\.url)).union([uninstallation.app.url])
        return update(
            selected,
            apps: [uninstallation.app.bundleIdentifier: (uninstallation.appStays(canUseHelper: canUseHelper), holds)],
            selectable: uninstallation.selectable(canUseHelper: canUseHelper),
            suggested: uninstallation.suggestedSelection(canUseHelper: canUseHelper)
        )
    }

    public mutating func update(_ selected: Set<URL>, in bulk: BulkUninstallation, canUseHelper: Bool) -> Set<URL> {
        var apps: [String: (stays: Bool, holds: Set<URL>)] = [:]
        for uninstallation in bulk.uninstallations {
            let identifier = uninstallation.app.bundleIdentifier
            let stays = uninstallation.appStays(canUseHelper: canUseHelper) || apps[identifier]?.stays == true
            apps[identifier] = (stays, Set(bulk.items.filter { $0.apps.contains(identifier) }.map(\.url)))
        }
        return update(
            selected,
            apps: apps,
            selectable: bulk.selectable(canUseHelper: canUseHelper),
            suggested: bulk.suggestedSelection(canUseHelper: canUseHelper)
        )
    }

    /// `apps` says, for each app by bundle identifier, whether it stays now and every item it holds.
    private mutating func update(
        _ selected: Set<URL>,
        apps: [String: (stays: Bool, holds: Set<URL>)],
        selectable: Set<URL>,
        suggested: Set<URL>
    ) -> Set<URL> {
        var suggested = suggested
        let isAsMade = selected == kept.made
        for (identifier, app) in apps {
            guard let before = stayed[identifier], before != app.stays else { continue }
            if app.stays || isAsMade {
                kept.forget(app.holds)
            } else {
                suggested.subtract(app.holds)
            }
        }
        stayed = apps.mapValues(\.stays)
        self.selectable = selectable
        return kept.update(selected, selectable: selectable, suggested: suggested)
    }
}
