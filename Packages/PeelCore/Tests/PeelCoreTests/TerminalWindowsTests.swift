import Foundation
@testable import PeelCore
import Testing

struct TerminalWindowsTests {
    @Test func theSwitchShowsOnlyWhereItChangesSomething() {
        #expect(!TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: nil))
        #expect(!TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: false as CFBoolean))
        #expect(!TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: 0 as CFNumber))
        #expect(TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: true as CFBoolean))
        #expect(TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: 1 as CFNumber))
        #expect(TerminalWindows.switchMatters(keptByTerminal: nil, readByTerminal: "YES" as CFString))
    }

    @Test func theSwitchStaysWhileTerminalHoldsItsOwnValue() {
        #expect(TerminalWindows.switchMatters(keptByTerminal: false, readByTerminal: false as CFBoolean))
        #expect(TerminalWindows.switchMatters(keptByTerminal: true, readByTerminal: true as CFBoolean))
    }

    @Test func aSwitchForOneAppNeverReadsTheGlobalDomain() throws {
        let domain = "org.example.peel.windows"
        let globalKeys =
            CFPreferencesCopyKeyList(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String] ?? []
        let held = try #require(globalKeys.lazy.compactMap { key -> (key: String, value: Tweak.Value)? in
            switch CFPreferencesCopyAppValue(key as CFString, domain as CFString) {
            case let text as String: (key, .text(text))
            case let number as NSNumber: (key, .number(number.doubleValue))
            default: nil
            }
        }.first)
        func tweak(_ kind: Tweak.Kind) -> Tweak {
            Tweak(
                id: "test",
                domain: domain,
                key: held.key,
                kind: kind,
                restart: .none,
                group: .terminal,
                hasASystemControl: false,
                documentation: .undocumented
            )
        }
        let store = TweakStore()
        #expect(store.state(of: tweak(.aSwitch(held.value))).isOn)
        #expect(!store.state(of: tweak(.aSwitchForThisAppAlone(held.value))).isOn)
        #expect(store.storedValue(of: tweak(.aSwitchForThisAppAlone(held.value))) == nil)
    }

    @Test func theSwitchMakesTerminalAloneCloseItsWindowsWhenItQuits() {
        let tweak = TweakCatalog.terminalWindows
        #expect(tweak.domain == "com.apple.Terminal")
        #expect(tweak.key == "NSQuitAlwaysKeepsWindows")
        #expect(tweak.kind == .aSwitchForThisAppAlone(.boolean(false)))
        #expect(tweak.group == .terminal)
        #expect(TweakCatalog.all.filter { $0.group == .terminal } == [tweak])
    }
}
