import Foundation
@testable import PeelCore
import PeelPrivileged
import Testing

struct TweakTests {
    @Test func everyTweakSaysWhatItChanges() {
        let identifiers = TweakCatalog.all.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)

        for tweak in TweakCatalog.all {
            #expect(!tweak.id.isEmpty)
            #expect(!tweak.domain.isEmpty)
            #expect(!tweak.key.isEmpty)
            #expect(!tweak.key.contains(" "), "\(tweak.id) has a key with a space in it")
        }
    }

    /// AppKit and HIToolbox read their keys once, when an app starts, so apps already open keep the old value.
    /// The row says so rather than asking for a log out, which would work but is not needed.
    /// Apple documents only a few of these keys; the rest are known from use alone, so a release can rename or ignore
    /// one without a word. Each tweak says which it is, and a documented one names Apple's page.
    @Test func everyTweakSaysWhereAppleDocumentsIt() {
        var documented: Set<String> = []
        for tweak in TweakCatalog.all {
            guard case .apple(let page) = tweak.documentation else { continue }
            documented.insert(tweak.id)
            #expect(page.scheme == "https" && (page.host() ?? "").hasSuffix("apple.com"), "\(tweak.id): \(page)")
        }
        let applesOwn: Set = [
            "dock-launchanim", "dock-static-only", "dock-show-recents", "dock-minimize-to-application",
            "finder-network-stores",
        ]
        #expect(documented == applesOwn)
    }

    @Test func dialogsOpenExpandedThroughTheKeysMacOSReads() {
        let keys = TweakCatalog.all.filter { $0.domain == TweakStore.globalDomain }.map(\.key)
        #expect(keys.contains("NSNavPanelExpandedStateForSaveMode"))
        #expect(keys.contains("PMPrintingExpandedStateForPrint"))
        #expect(!keys.contains("NSNavPanelExpandedStateForSaveMode2"))
        #expect(!keys.contains("PMPrintingExpandedStateForPrint2"))
    }

    @Test func asksForALogOutOnlyWhereAppleSaysItIsNeeded() {
        let logOut = TweakCatalog.all.filter { $0.restart == .logOut }.map(\.id)
        #expect(logOut == ["finder-network-stores"], "a log out is asked for where reopening the app is enough")
        #expect(TweakCatalog.all.first { $0.key == "AppleShowScrollBars" }?.restart == .relaunchApps)
        // `launchanim` is "Animate opening applications" in System Settings (`DesktopSettings.appex`).
        #expect(TweakCatalog.all.first { $0.key == "launchanim" }?.hasASystemControl == true)
    }

    /// Writing to these either fails silently or needs a permission Peel shouldn't ask for.
    @Test func neverWritesToADomainThatWouldFailSilently() {
        let forbidden = [
            "com.apple.universalaccess",
            "com.apple.Accessibility",
            "com.apple.Safari",
            "com.apple.mail",
            "com.apple.Notes",
            "com.apple.MobileSMS",
        ]
        for tweak in TweakCatalog.all {
            #expect(!forbidden.contains(tweak.domain), "\(tweak.id) writes to \(tweak.domain)")
            #expect(!tweak.domain.hasPrefix("/"), "\(tweak.id) points at a file rather than a domain")
        }
    }

    /// A switch is on when the key reads as what the switch writes, so each has to read back as itself.
    @Test func everySwitchReadsBackAsWhatItWrites() {
        for tweak in TweakCatalog.all {
            switch tweak.kind {
            case .aSwitch(let value), .aSwitchForThisAppAlone(let value):
                #expect(TweakStore.matches(TweakStore.property(value), value), "\(tweak.id) does not read back as what it writes")
            case .folder:
                #expect(tweak.group == .screenshots, "\(tweak.id) is a folder somewhere unexpected")
            }
        }
    }

    @Test func readsAValueBackAsTheSwitchThatWroteIt() {
        #expect(TweakStore.matches(true as CFBoolean, .boolean(true)))
        #expect(!TweakStore.matches(true as CFBoolean, .boolean(false)))
        // cfprefsd hands back a number for a boolean written by the command line.
        #expect(TweakStore.matches(1 as CFNumber, .boolean(true)))
        #expect(TweakStore.matches(0 as CFNumber, .boolean(false)))
        #expect(TweakStore.matches(0.0 as CFNumber, .number(0)))
        #expect(!TweakStore.matches(0.5 as CFNumber, .number(0)))
        #expect(TweakStore.matches("Always" as CFString, .text("Always")))
        #expect(!TweakStore.matches("Never" as CFString, .text("Always")))
        #expect(!TweakStore.matches("Always" as CFString, .boolean(true)))
        // Written without `-bool`, these are strings, which macOS still reads as a boolean.
        #expect(TweakStore.matches("YES" as CFString, .boolean(true)))
        #expect(TweakStore.matches("1" as CFString, .boolean(true)))
        #expect(TweakStore.matches("NO" as CFString, .boolean(false)))
    }

    @Test func callsTheGlobalDomainWhatTheApiCallsIt() {
        #expect(TweakStore.domain("NSGlobalDomain") == kCFPreferencesAnyApplication)
        #expect(TweakStore.domain("com.apple.dock") == "com.apple.dock" as CFString)
    }

    /// Reading is safe on any Mac: a key nobody has set reads as unset rather than as off.
    @Test func readsThisMacWithoutChangingIt() {
        let store = TweakStore()
        let nonsense = Tweak(
            id: "test",
            domain: "com.tuguidragos.Peel.NoSuchDomain",
            key: "NoSuchKeyAtAll",
            kind: .aSwitch(.boolean(true)),
            restart: .none,
            group: .dock,
            hasASystemControl: false,
            documentation: .undocumented
        )

        let state = store.state(of: nonsense)
        #expect(!state.isOn)
        #expect(!state.isManaged)
        #expect(store.storedValue(of: nonsense) == nil)

        // A tweak reads as on only when a value is stored for this user, a profile sets it, or it has a path.
        for tweak in TweakCatalog.all {
            let live = store.state(of: tweak)
            #expect(!live.isOn || live.isManaged || store.storedValue(of: tweak) != nil || live.path != nil, "\(tweak.id) reads as on with nothing stored")
        }
    }

    @Test func tellsWhetherThisMacHasSleepTurnedOff() {
        // Read-only: it just has to answer without failing on any Mac.
        _ = SleepSetting.isSleepDisabled()
        #expect(SleepSetting.undoCommand.hasPrefix("sudo pmset"))
    }

    /// The global domain is read with the primitive CFPreferences functions, not the "App" ones. On the Mac
    /// running the tests, Peel must see exactly what `defaults read -g` sees for every global tweak.
    @Test func readsTheGlobalDomainTheSameWayDefaultsDoes() async throws {
        let store = TweakStore()
        let global = TweakCatalog.all.filter { $0.domain == TweakStore.globalDomain }
        try #require(!global.isEmpty)

        for tweak in global {
            let peel = store.storedValue(of: tweak)
            let defaults = await Self.defaultsValue(key: tweak.key)
            #expect(
                (peel == nil) == (defaults == nil),
                "\(tweak.key): Peel read \(String(describing: peel)), defaults read \(String(describing: defaults))"
            )
            // `defaults` prints a boolean as 1 or 0 and everything else as it is stored.
            if let peel = peel as? NSNumber, let defaults {
                #expect(Double(defaults) == peel.doubleValue, "\(tweak.key): \(peel) vs \(defaults)")
            } else if let peel = peel as? String, let defaults {
                #expect(peel == defaults, "\(tweak.key): \(peel) vs \(defaults)")
            }
        }
    }

    /// What `defaults read -g` prints for `key`, run the way Peel runs every tool: with a time limit, and read
    /// without the call that raises an exception Swift cannot catch.
    private static func defaultsValue(key: String) async -> String? {
        guard case .success(let output) = await Subprocess.run("/usr/bin/defaults", ["read", "-g", key], timeout: 10), output.status == 0 else {
            return nil
        }
        return output.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
