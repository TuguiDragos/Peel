import Foundation
@testable import PeelCore
import Testing

struct KnownCasksTests {
    private func app(_ name: String, _ bundleIdentifier: String) -> InstalledApp {
        InstalledApp(
            url: URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory),
            bundleIdentifier: bundleIdentifier,
            name: name
        )
    }

    @Test func guessesTheNameHomebrewWouldUse() {
        #expect(CaskEvidence.tokens(for: app("Visual Studio Code", "com.microsoft.VSCode")).first == "visual-studio-code")
        #expect(CaskEvidence.tokens(for: app("iTerm2", "com.googlecode.iterm2")).first == "iterm2")
        #expect(CaskEvidence.tokens(for: app("YouTube to MP3", "com.mediahuman.y")).first == "youtube-to-mp3")
        #expect(CaskEvidence.tokens(for: app("1Password", "com.1password.1password")).first == "1password")
        // Punctuation collapses to one hyphen and never trails.
        #expect(CaskEvidence.tokens(for: app("Adobe  Photoshop!", "com.adobe.ps")).first == "adobe-photoshop")
        #expect(CaskEvidence.tokens(for: app("Zoom.us", "us.zoom.xos")).first == "zoom-us")
    }

    /// Homebrew's token does not always follow the app's name, so several spellings are tried. Each one is
    /// only a guess until the cask proves it is this app.
    @Test func triesTheSpellingsHomebrewActuallyUses() {
        #expect(CaskEvidence.tokens(for: app("AltTab", "com.lwouis.alt-tab-macos")).contains("alt-tab"))
        #expect(CaskEvidence.tokens(for: app("Hidden Bar", "com.dwarvesv.minimalbar")).contains("hiddenbar"))
        #expect(CaskEvidence.tokens(for: app("HandBrake", "fr.handbrake.HandBrake")).contains("handbrake-app"))
        #expect(CaskEvidence.tokens(for: app("Numi", "com.dmitrynikolaev.numi")) == ["numi", "numi-app"])
        #expect(CaskEvidence.tokens(for: app("YouTube to MP3", "com.mediahuman.y")).first == "youtube-to-mp3")
        #expect(CaskEvidence.tokens(for: app("iTerm2", "com.googlecode.iterm2")).contains("iterm2"))
    }

    /// A guessed name is never believed on its own: the cask has to prove it is this app.
    @Test func believesACaskOnlyWhenItProvesItIsTheApp() {
        let code = app("Visual Studio Code", "com.microsoft.VSCode")

        let byAppName = HomebrewPackage(name: "visual-studio-code", kind: .cask, appNames: ["Visual Studio Code.app"])
        #expect(CaskEvidence.proves(byAppName, isThe: code))

        let byQuit = HomebrewPackage(name: "visual-studio-code", kind: .cask, quitIdentifiers: ["com.microsoft.VSCode"])
        #expect(CaskEvidence.proves(byQuit, isThe: code))

        let unrelated = HomebrewPackage(name: "visual-studio-code", kind: .cask, appNames: ["Something Else.app"], quitIdentifiers: ["com.other.thing"])
        #expect(!CaskEvidence.proves(unrelated, isThe: code), "a cask that names another app was believed")

        let nothing = HomebrewPackage(name: "visual-studio-code", kind: .cask)
        #expect(!CaskEvidence.proves(nothing, isThe: code), "a cask that proves nothing was believed")

        let formula = HomebrewPackage(name: "visual-studio-code", kind: .formula, appNames: ["Visual Studio Code.app"])
        #expect(!CaskEvidence.proves(formula, isThe: code))
    }

    /// A cask that installs its app through a package has no app artifact to match, so its installer receipt
    /// is the proof.
    @Test func believesAPackageCaskWhenItsReceiptIsOnThisMac() {
        let adguard = app("AdGuard", "com.adguard.mac.adguard")
        let cask = HomebrewPackage(name: "adguard", kind: .cask, packageIdentifiers: ["com.adguard.mac.adguard-pkg"])

        #expect(CaskEvidence.proves(cask.noting(receipts: ["com.adguard.mac.adguard-pkg"]), isThe: adguard))
        #expect(!CaskEvidence.proves(cask, isThe: adguard), "a receipt that isn't installed was believed")
        #expect(!CaskEvidence.proves(cask.noting(receipts: ["com.someone.else"]), isThe: adguard))

        let wrongVendor = HomebrewPackage(name: "adguard", kind: .cask, packageIdentifiers: ["com.other.vendor-pkg"])
        #expect(!CaskEvidence.proves(wrongVendor.noting(receipts: ["com.other.vendor-pkg"]), isThe: adguard))

        // A receipt proves the app only if the app's identifier ends there or a separator follows it:
        // `com.adguard.mac.adguard2` is another product.
        let neighbor = HomebrewPackage(name: "adguard", kind: .cask, packageIdentifiers: ["com.adguard.mac.adguard2.pkg"])
        #expect(!CaskEvidence.proves(neighbor.noting(receipts: ["com.adguard.mac.adguard2.pkg"]), isThe: adguard))
    }

    /// Which receipts are installed is noted on the cask where they are known (`noting(receipts:)`), so every
    /// place that uses the cask (an uninstall, the inventory, an update check) reaches the same answer.
    @Test func aCaskProvenByItsReceiptStillGivesEvidence() throws {
        let directory = try TemporaryDirectory()
        try directory.directory("home/Library/Application Support/AdGuard")
        let adguard = app("AdGuard", "com.adguard.mac.adguard")
        let cask = HomebrewPackage(
            name: "adguard",
            kind: .cask,
            leftoverPatterns: ["~/Library/Application Support/AdGuard"],
            packageIdentifiers: ["com.adguard.mac.adguard-pkg"]
        )
        let home = directory.url.appending(path: "home", directoryHint: .isDirectory)

        #expect(CaskEvidence.evidence(for: adguard, casks: [cask], home: home) == nil)
        let combined = CaskEvidence.combined(installed: [cask], known: [], receipts: ["com.adguard.mac.adguard-pkg"])
        #expect(CaskEvidence.evidence(for: adguard, casks: combined, home: home)?.items.count == 1)
        #expect(CaskEvidence.cask(for: adguard, in: combined) != nil)
    }

    /// Two real casks install a `Caffeine.app`: `caffeine` quits `com.intelliscapesolutions.caffeine`, and
    /// `domzilla-caffeine` quits `net.domzilla.caffeine`. A file name is not proof against an identifier that
    /// says otherwise.
    @Test func aBundleNameIsNotEnoughWhenTheCaskQuitsSomeoneElse() {
        let domzilla = app("Caffeine", "net.domzilla.caffeine")
        let other = HomebrewPackage(name: "caffeine", kind: .cask, appNames: ["Caffeine.app"], quitIdentifiers: ["com.intelliscapesolutions.caffeine"])
        let own = HomebrewPackage(name: "domzilla-caffeine", kind: .cask, appNames: ["Caffeine.app"], quitIdentifiers: ["net.domzilla.caffeine"])
        let silent = HomebrewPackage(name: "caffeine", kind: .cask, appNames: ["Caffeine.app"])

        #expect(!CaskEvidence.proves(other, isThe: domzilla), "another product's cask was believed on the bundle's file name")
        #expect(CaskEvidence.proves(own, isThe: domzilla))
        #expect(CaskEvidence.proves(silent, isThe: domzilla))
    }

    /// Two makers can give their apps one name, and Homebrew keeps the plain token for the one that came first:
    /// here the `scribe` cask is one maker's editor, which ships `Scribe 2.app`, while another maker's app is
    /// `Scribe.app`. The token guessed from the name points to the wrong cask, and only the proof keeps Peel from
    /// offering one app's files as the other's.
    @Test func refusesACaskThatIsADifferentProductWithTheSameName() {
        let otherScribe = app("Scribe", "com.other.ScribeMac")
        let makersScribe = HomebrewPackage(
            name: "scribe",
            kind: .cask,
            appNames: ["Scribe 2.app"],
            leftoverPatterns: ["~/Library/Application Support/Maker/Scribe 2"]
        )

        #expect(CaskEvidence.tokens(for: otherScribe).contains("scribe"), "the guess lands on the wrong cask, as it must")
        #expect(!CaskEvidence.proves(makersScribe, isThe: otherScribe), "one product's files were offered under another's name")

        let real = HomebrewPackage(name: "other-scribe", kind: .cask, appNames: ["Scribe.app"], quitIdentifiers: ["com.other.ScribeMac"])
        #expect(CaskEvidence.proves(real, isThe: otherScribe))
    }

    /// An installed cask records where Homebrew put the app (`"target": "/Applications/Firefox.app"`). A second
    /// copy elsewhere is the same product, but it is not the copy `brew upgrade` changes.
    @Test func onlyTheCopyHomebrewPutThereIsHomebrews() throws {
        let json = Data(#"{"app": ["Firefox.app"], "target": "/Applications/Firefox.app"}"#.utf8)
        let artifact = try JSONDecoder().decode(CaskArtifact.self, from: json)
        #expect(artifact.appNames == ["Firefox.app"])
        #expect(artifact.appTargets == ["/Applications/Firefox.app"])

        let cask = HomebrewPackage(
            name: "firefox",
            kind: .cask,
            installedVersion: "130.0",
            appNames: artifact.appNames,
            appTargets: artifact.appTargets
        )
        let brewed = app("Firefox", "org.mozilla.firefox")
        let copy = InstalledApp(url: URL(filePath: "/Users/me/Applications/Firefox.app", directoryHint: .isDirectory), bundleIdentifier: "org.mozilla.firefox", name: "Firefox")

        #expect(CaskEvidence.installedCask(for: brewed, in: [cask]) != nil)
        #expect(CaskEvidence.installedCask(for: copy, in: [cask]) == nil, "a second copy was called Homebrew's")
        #expect(CaskEvidence.cask(for: copy, in: [cask]) != nil, "what the cask knows about the product still holds for the copy")
    }

    @Test func asksForNothingWhenThereIsNothingToAskAbout() async {
        #expect(await CaskEvidence.knownCasks(for: []).isEmpty)
    }

    /// Reads Homebrew's local copy of the cask definitions and finds nothing without Homebrew. The result
    /// depends on the machine running the test, so only its shape is checked: casks only, and no guessed token
    /// Homebrew does not know. That nothing is downloaded rests on `hasLocalDefinitions`, which a test cannot see.
    @Test func readsOnlyCasksHomebrewKnowsOnThisMac() async {
        let apps = [
            app("Visual Studio Code", "com.microsoft.VSCode"),
            app("Definitely Not A Real App", "com.example.nope"),
        ]
        let found = await CaskEvidence.knownCasks(for: apps)

        guard Homebrew.executableURL != nil else {
            #expect(found.isEmpty)
            return
        }
        #expect(found.allSatisfy { $0.kind == .cask })
        #expect(!found.contains { $0.name == "definitely-not-a-real-app" })
    }
}
