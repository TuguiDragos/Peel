import Foundation
@testable import PeelCore
import Testing

struct UninstallSelectionTests {
    private let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

    private func leftover(_ name: String, confidence: MatchConfidence = .certain, requiresPrivileges: Bool = false) -> Leftover {
        Leftover(
            url: URL(filePath: "/Users/me/Library/Caches/\(name)"),
            kind: .caches,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: []),
            size: 1_000,
            isMeasured: true,
            requiresPrivileges: requiresPrivileges
        )
    }

    private func uninstallation(appRequiresPrivileges: Bool = false, _ leftovers: [Leftover]) -> Uninstallation {
        Uninstallation(
            app: app,
            appSize: 10_000,
            appRequiresPrivileges: appRequiresPrivileges,
            scan: LeftoverScan(leftovers: leftovers, unreadableLocations: [])
        )
    }

    /// An app's page scans again when Homebrew's evidence arrives, when the exclusions change, and after a move.
    /// What the person deselected stays deselected through every one of those scans.
    @Test func anAppsPageKeepsWhatThePersonDeselectedWhenItScansAgain() {
        let first = leftover("com.example.app")
        let second = leftover("com.example.app.helper")
        let plan = uninstallation([first, second])
        var choices = UninstallSelection()

        var selected = choices.update([], in: plan, canUseHelper: true)
        #expect(selected == [app.url, first.url, second.url])
        selected.remove(first.url)

        #expect(choices.update(selected, in: plan, canUseHelper: true) == [app.url, second.url])
    }

    /// What needs the helper leaves the selection when the helper goes, and takes Peel's suggestion again once
    /// it is back, since the person could not choose it meanwhile.
    @Test func whatNeedsTheHelperFollowsTheHelper() {
        let own = leftover("com.example.app")
        let daemon = leftover("com.example.app.daemon.plist", requiresPrivileges: true)
        let plan = uninstallation([own, daemon])
        var choices = UninstallSelection()

        let selected = choices.update([], in: plan, canUseHelper: true)
        #expect(selected == [app.url, own.url, daemon.url])
        let withoutHelper = choices.update(selected, in: plan, canUseHelper: false)
        #expect(withoutHelper == [app.url, own.url])
        #expect(!choices.selectable.contains(daemon.url))
        #expect(choices.update(withoutHelper, in: plan, canUseHelper: true) == [app.url, own.url, daemon.url])
    }

    /// An app that needs the helper stays when the helper goes. Everything selected was chosen for it going, the
    /// person's own picks included, so nothing stays selected: its leftovers would go and it would stay without them.
    @Test func anAppThatComesToStayHasNothingSelected() {
        let own = leftover("com.example.app")
        let possible = leftover("Example", confidence: .possible)
        let plan = uninstallation(appRequiresPrivileges: true, [own, possible])
        var choices = UninstallSelection()

        var selected = choices.update([], in: plan, canUseHelper: true)
        #expect(selected == [app.url, own.url])
        selected.insert(possible.url)

        #expect(choices.update(selected, in: plan, canUseHelper: false).isEmpty)
    }

    /// When the helper comes back, the app can go again. Peel's suggestion comes back only when the person left
    /// the selection as Peel made it; what they chose meanwhile is theirs, and the app is not selected for them.
    @Test func anAppThatCanGoAgainGetsTheSuggestionOnlyIfNothingWasChanged() {
        let own = leftover("com.example.app")
        let possible = leftover("Example", confidence: .possible)
        let plan = uninstallation(appRequiresPrivileges: true, [own, possible])

        var untouched = UninstallSelection()
        let nothing = untouched.update([], in: plan, canUseHelper: false)
        #expect(nothing.isEmpty)
        #expect(untouched.update(nothing, in: plan, canUseHelper: true) == [app.url, own.url])

        var changed = UninstallSelection()
        _ = changed.update([], in: plan, canUseHelper: false)
        #expect(changed.update([possible.url], in: plan, canUseHelper: true) == [possible.url])
    }
}
