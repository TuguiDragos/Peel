public import Foundation

/// What is selected on an app's page, kept across its scans (`KeptSelection`) and as the helper comes and goes.
///
/// When the app comes to stay, everything selected was chosen for it going, so nothing stays selected: its leftovers
/// would go and it would stay without them. When it can go again, Peel's suggestion comes back only if the person
/// left the selection as Peel made it.
public struct UninstallSelection: Sendable {
    private var kept = KeptSelection()
    private var appStays: Bool?
    /// What a checkbox can select as of the last update.
    public private(set) var selectable: Set<URL> = []

    public init() {}

    public mutating func update(_ selected: Set<URL>, in uninstallation: Uninstallation, canUseHelper: Bool) -> Set<URL> {
        let stays = uninstallation.appStays(canUseHelper: canUseHelper)
        var suggested = uninstallation.suggestedSelection(canUseHelper: canUseHelper)
        if let stayed = appStays, stayed != stays {
            if stays || selected == kept.made {
                kept.startOver()
            } else {
                suggested = []
            }
        }
        appStays = stays
        selectable = uninstallation.selectable(canUseHelper: canUseHelper)
        return kept.update(selected, selectable: selectable, suggested: suggested)
    }
}
