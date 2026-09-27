public import Foundation

/// What is selected on an app's page, or on several apps' page, kept across its scans (`KeptSelection`) and as the
/// helper comes and goes.
///
/// When an app comes to stay, what it holds was chosen for it going, so none of it stays selected: its files would
/// go and leave it without them. When it can go again, Peel's suggestion comes back for it only if the person left
/// the selection as Peel made it. On several apps' page, an app whose bundle the person deselects stays too, and
/// selecting the bundle again brings back its files as they were (`personChanged(from:to:in:)`). Two copies of an
/// app share its files, which stay while either copy does, and each copy's bundle goes or stays on its own.
public struct UninstallSelection: Sendable {
    /// Whether an app stays, and what it holds: its files, and the bundle of each chosen copy.
    private struct App {
        var stays: Bool
        var files: Set<URL>
        var bundles: Set<URL>
    }

    private var kept = KeptSelection()
    /// Whether each app stayed at the last change, by bundle identifier.
    private var stayed: [String: Bool] = [:]
    /// The files each app the person keeps had selected when they kept it, by bundle identifier.
    private var setAside: [String: Set<URL>] = [:]
    /// What a checkbox can select as of the last update.
    public private(set) var selectable: Set<URL> = []

    public init() {}

    public mutating func update(_ selected: Set<URL>, in uninstallation: Uninstallation, canUseHelper: Bool) -> Set<URL> {
        let app = App(
            stays: uninstallation.appStays(canUseHelper: canUseHelper),
            files: Set(uninstallation.scan.leftovers.map(\.url)),
            bundles: [uninstallation.app.url]
        )
        return update(
            selected,
            apps: [uninstallation.app.bundleIdentifier: app],
            selectable: uninstallation.selectable(canUseHelper: canUseHelper),
            suggested: uninstallation.suggestedSelection(canUseHelper: canUseHelper)
        )
    }

    public mutating func update(_ selected: Set<URL>, in bulk: BulkUninstallation, canUseHelper: Bool) -> Set<URL> {
        let selectable = bulk.selectable(canUseHelper: canUseHelper)
        var apps: [String: App] = [:]
        for uninstallation in bulk.uninstallations {
            let identifier = uninstallation.app.bundleIdentifier
            let bundle = uninstallation.app.url
            let isKept = kept.hasOffered(bundle) && selectable.contains(bundle) && !selected.contains(bundle)
            var app = apps[identifier] ?? App(stays: false, files: bulk.files(of: identifier), bundles: [])
            app.stays = app.stays || uninstallation.appStays(canUseHelper: canUseHelper) || isKept
            app.bundles.insert(bundle)
            apps[identifier] = app
        }
        return update(
            selected,
            apps: apps,
            selectable: selectable,
            suggested: bulk.suggestedSelection(canUseHelper: canUseHelper)
        )
    }

    /// Carries a change the person made on several apps' page from `previous` to `selected` over to the files of
    /// each app it touches: an app whose bundle they deselect stays, so none of its files stays selected, and once
    /// every copy of it is selected again its files come back as they were.
    public mutating func personChanged(
        from previous: Set<URL>,
        to selected: Set<URL>,
        in bulk: BulkUninstallation
    ) -> Set<URL> {
        let staying = bulk.staying(selected: selected)
        var result = selected
        for identifier in bulk.staying(selected: previous).symmetricDifference(staying) {
            let files = bulk.files(of: identifier)
            if staying.contains(identifier) {
                setAside[identifier] = result.intersection(files)
                result.subtract(files)
            } else {
                result.formUnion((setAside.removeValue(forKey: identifier) ?? []).intersection(selectable))
            }
            stayed[identifier] = staying.contains(identifier)
        }
        return result
    }

    /// `apps` says, for each app by bundle identifier, whether it stays now and what it holds.
    private mutating func update(
        _ selected: Set<URL>,
        apps: [String: App],
        selectable: Set<URL>,
        suggested: Set<URL>
    ) -> Set<URL> {
        var suggested = suggested
        let isAsMade = selected == kept.made
        for (identifier, app) in apps {
            if app.stays {
                suggested.subtract(app.files)
            }
            guard let before = stayed[identifier], before != app.stays else { continue }
            let holds = app.files.union(app.bundles)
            if app.stays || isAsMade {
                kept.forget(holds)
            } else {
                suggested.subtract(holds)
            }
        }
        stayed = apps.mapValues(\.stays)
        self.selectable = selectable
        return kept.update(selected, selectable: selectable, suggested: suggested)
    }
}
