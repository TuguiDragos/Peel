import Foundation

public enum TerminalWindows {
    public static func switchMatters(in store: TweakStore = TweakStore()) -> Bool {
        let tweak = TweakCatalog.terminalWindows
        return switchMatters(keptByTerminal: store.storedValue(of: tweak), readByTerminal: store.valueInEffect(of: tweak))
    }

    static func switchMatters(keptByTerminal: Any?, readByTerminal: CFPropertyList?) -> Bool {
        keptByTerminal != nil || readByTerminal.map { TweakStore.matches($0, .boolean(true)) } == true
    }
}
