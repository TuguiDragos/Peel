import Foundation
@testable import PeelCore
import Testing

struct UninstallSelectionTests {
    private let app = InstalledApp(url: URL(filePath: "/Applications/Example.app"), bundleIdentifier: "com.example.app", name: "Example")

    private func leftover(
        _ name: String,
        confidence: MatchConfidence = .certain,
        requiresPrivileges: Bool = false
    ) -> Leftover {
        Leftover(
            url: URL(filePath: "/Users/me/Library/Caches/\(name)"),
            kind: .caches,
            match: LeftoverMatch(reason: .bundleIdentifier, confidence: confidence, sharedWith: []),
            size: 1_000,
            isMeasured: true,
            requiresPrivileges: requiresPrivileges
        )
    }

    private let other = InstalledApp(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.example.other", name: "Other")

    private func uninstallation(
        of app: InstalledApp? = nil,
        appRequiresPrivileges: Bool = false,
        _ leftovers: [Leftover]
    ) -> Uninstallation {
        Uninstallation(
            app: app ?? self.app,
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

    /// Several apps' page keeps what the person deselected through its scans, as an app's own page does.
    @Test func severalAppsKeepWhatThePersonDeselectedWhenTheyScanAgain() {
        let own = leftover("com.example.app")
        let others = leftover("com.example.other")
        let bulk = BulkUninstallation(uninstallations: [uninstallation([own]), uninstallation(of: other, [others])])
        var choices = UninstallSelection()

        var selected = choices.update([], in: bulk, canUseHelper: true)
        #expect(selected == [app.url, own.url, other.url, others.url])
        selected.remove(own.url)

        #expect(choices.update(selected, in: bulk, canUseHelper: true) == [app.url, other.url, others.url])
    }

    /// When one of several apps comes to stay, what it holds leaves the selection, the files it shares with the
    /// other chosen apps included, and the others keep theirs.
    @Test func whenOneOfSeveralAppsComesToStayOnlyItsFilesLeaveTheSelection() {
        let own = leftover("com.example.app")
        let possible = leftover("Example", confidence: .possible)
        let shared = leftover("com.example.shared")
        let others = leftover("com.example.other")
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(appRequiresPrivileges: true, [own, possible, shared]),
            uninstallation(of: other, [others, shared]),
        ])
        var choices = UninstallSelection()

        var selected = choices.update([], in: bulk, canUseHelper: true)
        #expect(selected == [app.url, own.url, shared.url, other.url, others.url])
        selected.insert(possible.url)

        #expect(choices.update(selected, in: bulk, canUseHelper: false) == [other.url, others.url])
    }

    /// When one of several apps can go again, Peel's suggestion comes back for it only if nothing on the page was
    /// changed meanwhile.
    @Test func oneOfSeveralAppsThatCanGoAgainGetsTheSuggestionOnlyIfNothingWasChanged() {
        let own = leftover("com.example.app")
        let others = leftover("com.example.other")
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation(appRequiresPrivileges: true, [own]),
            uninstallation(of: other, [others]),
        ])

        var untouched = UninstallSelection()
        let first = untouched.update([], in: bulk, canUseHelper: false)
        #expect(first == [other.url, others.url])
        #expect(untouched.update(first, in: bulk, canUseHelper: true) == [app.url, own.url, other.url, others.url])

        var changed = UninstallSelection()
        _ = changed.update([], in: bulk, canUseHelper: false)
        #expect(changed.update([other.url], in: bulk, canUseHelper: true) == [other.url])
    }

    /// On several apps' page, deselecting one app's bundle keeps that app, so its files leave the selection, the
    /// file it shares with another chosen app included, and the other app keeps its own.
    @Test func deselectingOneOfSeveralAppsLeavesItsFiles() {
        let own = leftover("com.example.app")
        let others = leftover("com.example.other")
        let shared = leftover("com.example.shared")
        let bulk = BulkUninstallation(uninstallations: [
            uninstallation([own, shared]), uninstallation(of: other, [others, shared]),
        ])
        var choices = UninstallSelection()
        let suggested = choices.update([], in: bulk, canUseHelper: true)
        #expect(suggested == [app.url, own.url, shared.url, other.url, others.url])

        let selected = choices.personChanged(from: suggested, to: suggested.subtracting([other.url]), in: bulk)
        #expect(selected == [app.url, own.url])
        #expect(bulk.staying(selected: selected) == [other.bundleIdentifier])
    }

    /// Selecting the bundle again brings back the app's files as they were, and nothing more: a file the person had
    /// deselected before stays deselected.
    @Test func selectingTheBundleAgainBringsBackWhatWasSelected() {
        let others = leftover("com.example.other")
        let agent = leftover("com.example.other.agent")
        let bulk = BulkUninstallation(uninstallations: [uninstallation([]), uninstallation(of: other, [others, agent])])
        var choices = UninstallSelection()
        var selected = choices.update([], in: bulk, canUseHelper: true)
        selected = choices.personChanged(from: selected, to: selected.subtracting([agent.url]), in: bulk)

        selected = choices.personChanged(from: selected, to: selected.subtracting([other.url]), in: bulk)
        #expect(selected == [app.url])
        #expect(
            choices.personChanged(from: selected, to: selected.union([other.url]), in: bulk) == [
                app.url, other.url, others.url,
            ]
        )
    }

    /// An app the person keeps stays kept through the page's scans: a file of it found later is not selected.
    @Test func aScanAfterAnAppWasKeptSelectsNothingOfIt() {
        let others = leftover("com.example.other")
        let later = leftover("com.example.other.later")
        let before = BulkUninstallation(uninstallations: [uninstallation([]), uninstallation(of: other, [others])])
        var choices = UninstallSelection()
        var selected = choices.update([], in: before, canUseHelper: true)
        selected = choices.personChanged(from: selected, to: selected.subtracting([other.url]), in: before)

        let after = BulkUninstallation(uninstallations: [
            uninstallation([]), uninstallation(of: other, [others, later]),
        ])
        #expect(choices.update(selected, in: after, canUseHelper: true) == [app.url])
    }

    /// Two copies of one app share its files, which stay while either copy does. Keeping one copy keeps them, and
    /// the other copy can still go, through the page's scans too.
    @Test func keepingOneOfTwoCopiesKeepsTheirFilesAndLetsTheOtherGo() {
        let copy = InstalledApp(url: URL(filePath: "/Users/me/Applications/Example.app"), bundleIdentifier: app.bundleIdentifier, name: app.name)
        let own = leftover("com.example.app")
        let bulk = BulkUninstallation(uninstallations: [uninstallation([own]), uninstallation(of: copy, [own])])
        var choices = UninstallSelection()
        let suggested = choices.update([], in: bulk, canUseHelper: true)
        #expect(suggested == [app.url, copy.url, own.url])

        let selected = choices.personChanged(from: suggested, to: suggested.subtracting([copy.url]), in: bulk)
        #expect(selected == [app.url])
        #expect(choices.update(selected, in: bulk, canUseHelper: true) == [app.url])
    }

    /// The files of two copies come back only once both are selected again.
    @Test func theFilesOfTwoCopiesComeBackOnceBothAreSelectedAgain() {
        let copy = InstalledApp(url: URL(filePath: "/Users/me/Applications/Example.app"), bundleIdentifier: app.bundleIdentifier, name: app.name)
        let own = leftover("com.example.app")
        let bulk = BulkUninstallation(uninstallations: [uninstallation([own]), uninstallation(of: copy, [own])])
        var choices = UninstallSelection()
        var selected = choices.update([], in: bulk, canUseHelper: true)

        selected = choices.personChanged(from: selected, to: selected.subtracting([copy.url]), in: bulk)
        selected = choices.personChanged(from: selected, to: selected.subtracting([app.url]), in: bulk)
        selected = choices.personChanged(from: selected, to: selected.union([app.url]), in: bulk)
        #expect(selected == [app.url])
        #expect(
            choices.personChanged(from: selected, to: selected.union([copy.url]), in: bulk) == [
                app.url, copy.url, own.url,
            ]
        )
    }
}
