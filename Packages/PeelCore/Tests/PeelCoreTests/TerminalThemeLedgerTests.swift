import Foundation
@testable import PeelCore
import Testing

private final class InMemoryTerminalSettings: TerminalSettingsStoring {
    var isTerminalOpen = false
    var isManaged = false
    var refusesWrites = false
    var refusesNames = false
    var storedProfiles: [String: [String: Any]] = ["Basic": ["name": "Basic"], "Pro": ["name": "Pro"]]
    var names: [TerminalProfileRole: String] = [.newWindows: "Basic", .startup: "Basic"]

    func profiles() -> [String: [String: Any]] {
        storedProfiles
    }

    func setProfiles(_ profiles: [String: [String: Any]]) -> Bool {
        guard !refusesWrites else { return false }
        storedProfiles = profiles
        return true
    }

    func profileName(for role: TerminalProfileRole) -> String? {
        names[role]
    }

    func setProfileName(_ name: String?, for role: TerminalProfileRole) -> Bool {
        guard !refusesWrites, !refusesNames else { return false }
        names[role] = name
        return true
    }
}

struct TerminalThemeLedgerTests {
    private let theme = TerminalThemeCatalog.all[0]
    private let otherTheme = TerminalThemeCatalog.all[1]

    @Test func aThemeInUseOpensEveryTerminalWindowWithIt() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .changed)
        let written = try #require(terminal.storedProfiles[theme.profileName])
        #expect(
            TerminalProfile.fingerprint(of: written)
                == TerminalProfile.fingerprint(of: try TerminalProfile.settings(for: theme))
        )
        #expect(terminal.storedProfiles["Basic"] != nil)
        #expect(terminal.names == [.newWindows: theme.profileName, .startup: theme.profileName])
        #expect(ledger.theme(in: terminal) == theme)
        #expect(ledger.canPutBack)
    }

    @Test func puttingBackGivesTerminalItsProfilesBackAndTakesPeelsAway() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.names[.startup] = "Pro"
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        _ = try ledger.use(otherTheme, in: terminal)

        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Pro"])
        #expect(Set(terminal.storedProfiles.keys) == ["Basic", "Pro"])
        #expect(ledger.theme(in: terminal) == nil)
        #expect(!ledger.canPutBack)
    }

    @Test func puttingBackLeavesNoChoiceWhereTerminalHadNone() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.names = [:]
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)

        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.names.isEmpty)
    }

    @Test func nothingChangesWhileTerminalIsOpen() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.isTerminalOpen = true
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .terminalIsOpen)
        #expect(terminal.storedProfiles[theme.profileName] == nil)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
        #expect(!ledger.canPutBack)

        terminal.isTerminalOpen = false
        _ = try ledger.use(theme, in: terminal)
        terminal.isTerminalOpen = true
        #expect(ledger.putBack(in: terminal) == .terminalIsOpen)
        #expect(terminal.names[.newWindows] == theme.profileName)
        #expect(ledger.canPutBack)
    }

    @Test func nothingChangesWhileAProfileManagesTerminal() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.isManaged = true
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .managed)
        #expect(terminal.storedProfiles[theme.profileName] == nil)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aThemeThePersonChangedIsNeitherWrittenOverNorTakenAway() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        terminal.storedProfiles[theme.profileName]?["columnCount"] = 80

        #expect(try ledger.use(theme, in: terminal) == .unchanged)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aProfileThePersonChoseSinceStaysWhenPeelPutsBack() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        terminal.names[.newWindows] = "Pro"

        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.names == [.newWindows: "Pro", .startup: "Basic"])
        #expect(terminal.storedProfiles[theme.profileName] == nil)
    }

    @Test func aPeelThemeStillInUseIsKept() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        _ = try ledger.use(otherTheme, in: terminal)
        terminal.names[.startup] = theme.profileName

        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.names == [.newWindows: "Basic", .startup: theme.profileName])
        #expect(terminal.storedProfiles[theme.profileName] != nil)
        #expect(terminal.storedProfiles[otherTheme.profileName] == nil)
    }

    @Test func aWriteTerminalRefusesLeavesEverythingAsItWas() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.refusesWrites = true
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .refused)
        #expect(!ledger.canPutBack)
        #expect(ledger.written.isEmpty)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aChoiceTerminalRefusesStillLetsPeelTakeItsThemeAway() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.refusesNames = true
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .refused)
        #expect(terminal.storedProfiles[theme.profileName] != nil)
        terminal.refusesNames = false
        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName] == nil)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aProfileNamedLikePeelsThatPeelNeverWroteIsLeftAsItIs() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.storedProfiles[theme.profileName] = ["name": theme.profileName, "columnCount": 80]
        var ledger = TerminalThemeLedger()

        #expect(try ledger.use(theme, in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
    }

    @Test func peelBringsItsOwnUntouchedThemeUpToDate() throws {
        let terminal = InMemoryTerminalSettings()
        var older = try TerminalProfile.settings(for: theme)
        older["TextColor"] = Data([1, 2, 3])
        terminal.storedProfiles[theme.profileName] = older
        let olderFingerprint = try #require(TerminalProfile.fingerprint(of: older))
        var ledger = TerminalThemeLedger(stored: ["written": [theme.profileName: olderFingerprint]])

        #expect(try ledger.use(theme, in: terminal) == .changed)
        let current = try #require(terminal.storedProfiles[theme.profileName])
        #expect(
            TerminalProfile.fingerprint(of: current)
                == TerminalProfile.fingerprint(of: try TerminalProfile.settings(for: theme))
        )
    }

    @Test func theLedgerReadsBackWhatItStored() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)

        var copy = TerminalThemeLedger(stored: ledger.stored)
        #expect(copy.before == ledger.before)
        #expect(copy.chosen == ledger.chosen)
        #expect(copy.written == ledger.written)
        #expect(copy.putBack(in: terminal) == .changed)
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aFingerprintFollowsTheProfileAndNothingElse() throws {
        let settings = try TerminalProfile.settings(for: theme)
        let fingerprint = try #require(TerminalProfile.fingerprint(of: settings))
        #expect(TerminalProfile.fingerprint(of: try TerminalProfile.settings(for: theme)) == fingerprint)
        var changed = settings
        changed["rowCount"] = 31
        #expect(TerminalProfile.fingerprint(of: changed) != fingerprint)
    }
}

struct TerminalOptionTests {
    private let theme = TerminalThemeCatalog.all[0]
    private let otherTheme = TerminalThemeCatalog.all[1]

    private func terminalUsing(_ theme: TerminalTheme) throws -> (InMemoryTerminalSettings, TerminalThemeLedger) {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        return (terminal, ledger)
    }

    @Test func anOptionChangesOnlyItsOwnKeyInTheThemeInUse() throws {
        var (terminal, ledger) = try terminalUsing(theme)

        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .changed)
        var profile = try #require(terminal.storedProfiles[theme.profileName])
        #expect(profile["useOptionAsMetaKey"] as? Bool == true)
        #expect(ledger.options(in: terminal) == [.optionAsMeta])
        profile["useOptionAsMetaKey"] = nil
        #expect(
            TerminalProfile.fingerprint(of: profile)
                == TerminalProfile.fingerprint(of: try TerminalProfile.settings(for: theme))
        )

        #expect(ledger.set(.noAlertSound, to: true, in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["Bell"] as? Bool == false)
        #expect(ledger.options(in: terminal) == [.optionAsMeta, .noAlertSound])
        #expect(ledger.set(.noAlertSound, to: true, in: terminal) == .unchanged)
    }

    @Test func anOptionTurnedOffLeavesTheKeyToTerminalAsApplesOwnProfilesDo() throws {
        let apple = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: TerminalThemeTests.clearDark), format: nil)
                as? [String: Any]
        )
        for option in TerminalOption.allCases {
            #expect(apple[option.rawValue] == nil)
        }
        var (terminal, ledger) = try terminalUsing(theme)
        _ = ledger.set(.optionAsMeta, to: true, in: terminal)
        _ = ledger.set(.noAlertSound, to: true, in: terminal)

        #expect(ledger.set(.optionAsMeta, to: false, in: terminal) == .changed)
        #expect(ledger.set(.noAlertSound, to: false, in: terminal) == .changed)
        let profile = try #require(terminal.storedProfiles[theme.profileName])
        #expect(
            TerminalProfile.fingerprint(of: profile)
                == TerminalProfile.fingerprint(of: try TerminalProfile.settings(for: theme))
        )
        #expect(ledger.options(in: terminal) == [])
    }

    @Test func theOptionsGoWithThePersonToAnotherTheme() throws {
        var (terminal, ledger) = try terminalUsing(theme)
        _ = ledger.set(.optionAsMeta, to: true, in: terminal)
        _ = ledger.set(.noAlertSound, to: true, in: terminal)

        #expect(try ledger.use(otherTheme, in: terminal) == .changed)
        #expect(ledger.options(in: terminal) == [.optionAsMeta, .noAlertSound])
        let profile = try #require(terminal.storedProfiles[otherTheme.profileName])
        #expect(
            TerminalProfile.fingerprint(of: profile)
                == TerminalProfile.fingerprint(
                    of: try TerminalProfile.settings(for: otherTheme, options: [.optionAsMeta, .noAlertSound])
                )
        )

        _ = ledger.set(.optionAsMeta, to: false, in: terminal)
        #expect(try ledger.use(theme, in: terminal) == .changed)
        #expect(ledger.options(in: terminal) == [.noAlertSound])
    }

    @Test func peelStillTakesItsThemesAwayAfterChangingAnOption() throws {
        var (terminal, ledger) = try terminalUsing(theme)
        _ = ledger.set(.optionAsMeta, to: true, in: terminal)

        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(Set(terminal.storedProfiles.keys) == ["Basic", "Pro"])
        #expect(terminal.names == [.newWindows: "Basic", .startup: "Basic"])
    }

    @Test func aThemeThePersonChangedKeepsTheirChangesAndStaysTheirs() throws {
        var (terminal, ledger) = try terminalUsing(theme)
        terminal.storedProfiles[theme.profileName]?["columnCount"] = 80

        #expect(ledger.set(.noAlertSound, to: true, in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
        #expect(terminal.storedProfiles[theme.profileName]?["Bell"] as? Bool == false)
        #expect(ledger.putBack(in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName] != nil)
    }

    @Test func anOptionChangesAPeelThemeInUseThatPeelNeverWrote() throws {
        let terminal = InMemoryTerminalSettings()
        terminal.storedProfiles[theme.profileName] = ["name": theme.profileName, "columnCount": 80]
        terminal.names[.newWindows] = theme.profileName
        var ledger = TerminalThemeLedger()

        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .changed)
        #expect(terminal.storedProfiles[theme.profileName]?["useOptionAsMetaKey"] as? Bool == true)
        #expect(terminal.storedProfiles[theme.profileName]?["columnCount"] as? Int == 80)
        _ = ledger.putBack(in: terminal)
        #expect(terminal.storedProfiles[theme.profileName] != nil, "Put Back took away a profile Peel never wrote")
    }

    @Test func theOptionsBelongToPeelsThemesAlone() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()

        #expect(ledger.options(in: terminal) == nil)
        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .unchanged)
        #expect(terminal.storedProfiles["Basic"]?["useOptionAsMetaKey"] == nil)
    }

    @Test func nothingChangesWhileTerminalIsOpenOrLockedOrRefusing() throws {
        var (terminal, ledger) = try terminalUsing(theme)
        let written = ledger.written

        terminal.isTerminalOpen = true
        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .terminalIsOpen)
        terminal.isTerminalOpen = false
        terminal.isManaged = true
        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .managed)
        terminal.isManaged = false
        terminal.refusesWrites = true
        #expect(ledger.set(.optionAsMeta, to: true, in: terminal) == .refused)

        #expect(terminal.storedProfiles[theme.profileName]?["useOptionAsMetaKey"] == nil)
        #expect(ledger.written == written)
    }

    @Test func readsTheOptionsTerminalStoresAsNumbers() throws {
        let terminal = InMemoryTerminalSettings()
        var ledger = TerminalThemeLedger()
        _ = try ledger.use(theme, in: terminal)
        terminal.storedProfiles[theme.profileName]?["useOptionAsMetaKey"] = 1
        terminal.storedProfiles[theme.profileName]?["Bell"] = 0

        #expect(ledger.options(in: terminal) == [.optionAsMeta, .noAlertSound])
        terminal.storedProfiles[theme.profileName]?["Bell"] = 1
        #expect(ledger.options(in: terminal) == [.optionAsMeta])
    }
}
