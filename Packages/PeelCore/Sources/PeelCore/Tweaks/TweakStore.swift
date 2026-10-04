import Foundation
import Synchronization
internal import PeelPrivileged

/// Reads and writes tweak settings through CFPreferences, never by editing a plist file. cfprefsd keeps its own
/// copy of each domain and writes it back over any change made to the file directly.
public struct TweakStore: Sendable, TweakStoring {
    /// The global domain as the command line names it. CFPreferences names it `kCFPreferencesAnyApplication`,
    /// and CFPreferences.h says the "App" functions "should never be called with kCFPreferencesAnyApplication".
    /// So this domain is read and written with the primitive functions, for this user on any host. Every other
    /// domain uses the "App" functions.
    static let globalDomain = "NSGlobalDomain"

    public init() {}

    /// The domains already synchronized since `beginReading()`, so reading every tweak synchronizes each domain
    /// once rather than once per key.
    private let synchronized = Domains()

    private final class Domains: Sendable {
        private let names = Mutex<Set<String>>([])

        func isFirst(_ domain: String) -> Bool {
            names.withLock { $0.insert(domain).inserted }
        }

        func forget() {
            names.withLock { $0.removeAll() }
        }
    }

    private func synchronizeOnce(_ domain: String) {
        if synchronized.isFirst(domain) { _ = Self.synchronize(domain) }
    }

    /// Starts a new reading of every tweak: each domain is synchronized again before its first key is read.
    public func beginReading() {
        synchronized.forget()
    }

    public func state(of tweak: Tweak) -> TweakState {
        let key = tweak.key as CFString
        synchronizeOnce(tweak.domain)

        let isManaged = Self.isForced(key, in: tweak.domain)
        let read = switch tweak.kind {
        case .aSwitchForThisAppAlone: Self.copyStored(key, from: tweak.domain)
        case .aSwitch, .folder, .name: Self.copy(key, from: tweak.domain)
        }
        guard let current = read else {
            return TweakState(isOn: false, isManaged: isManaged, text: nil)
        }

        switch tweak.kind {
        case .aSwitch(let wanted), .aSwitchForThisAppAlone(let wanted):
            return TweakState(isOn: Self.matches(current, wanted), isManaged: isManaged, text: nil)
        case .folder, .name:
            let text = current as? String
            return TweakState(isOn: text?.isEmpty == false, isManaged: isManaged, text: text)
        }
    }

    /// Returns what the key holds in the layer Peel writes (this user, any host), so it can be put back exactly
    /// as it was. `nil` means the key is absent there, and putting that back removes the key.
    ///
    /// `state(of:)` can read a value from an administrator's file or from ByHost instead. If Peel recorded such
    /// a value and put it back, the value would be copied into the user's own domain, and the administrator's
    /// later changes would not take effect.
    public func storedValue(of tweak: Tweak) -> Any? {
        _ = Self.synchronize(tweak.domain)
        return Self.copyStored(tweak.key as CFString, from: tweak.domain)
    }

    func valueInEffect(of tweak: Tweak) -> CFPropertyList? {
        _ = Self.synchronize(Self.globalDomain)
        _ = Self.synchronize(tweak.domain)
        return Self.copy(tweak.key as CFString, from: tweak.domain)
    }

    /// Writes back `value`, or removes the key when `value` is `nil`, so macOS falls back to its default.
    @discardableResult
    public func restore(_ value: Any?, for tweak: Tweak) -> Bool {
        write(value as CFPropertyList?, for: tweak)
    }

    /// Writes the value that turns `tweak` on, or `text`, the path or the name, for a folder or a name tweak.
    @discardableResult
    public func turnOn(_ tweak: Tweak, text: String? = nil) -> Bool {
        let value: CFPropertyList? = switch tweak.kind {
        case .aSwitch(let wanted), .aSwitchForThisAppAlone(let wanted): Self.property(wanted)
        case .folder, .name: text.map { $0 as CFString }
        }
        guard let value else { return false }
        return write(value, for: tweak)
    }

    private func write(_ value: CFPropertyList?, for tweak: Tweak) -> Bool {
        let key = tweak.key as CFString
        guard !Self.isForced(key, in: tweak.domain) else { return false }
        Self.set(key, to: value, in: tweak.domain)
        return Self.synchronize(tweak.domain)
    }

    static func domain(_ name: String) -> CFString {
        name == globalDomain ? kCFPreferencesAnyApplication : name as CFString
    }

    private static func copy(_ key: CFString, from name: String) -> CFPropertyList? {
        name == globalDomain
            ? CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            : CFPreferencesCopyAppValue(key, name as CFString)
    }

    private static func copyStored(_ key: CFString, from name: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key, domain(name), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func set(_ key: CFString, to value: CFPropertyList?, in name: String) {
        if name == globalDomain {
            CFPreferencesSetValue(key, value, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        } else {
            CFPreferencesSetAppValue(key, value, name as CFString)
        }
    }

    private static func synchronize(_ name: String) -> Bool {
        name == globalDomain
            ? CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            : CFPreferencesAppSynchronize(name as CFString)
    }

    /// Returns whether `key` is managed, for example by a configuration profile. `CFPreferencesAppValueIsForced`
    /// is an "App" function, so for the global domain this reads the managed preferences files directly.
    static func isForced(_ key: CFString, in name: String) -> Bool {
        guard name == globalDomain else { return CFPreferencesAppValueIsForced(key, name as CFString) }
        let user = NSUserName()
        return ["/Library/Managed Preferences/\(user)/.GlobalPreferences.plist", "/Library/Managed Preferences/.GlobalPreferences.plist"]
            .contains { path in
                guard
                    let data = FileManager.default.contents(atPath: path),
                    let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { return false }
                return plist[key as String] != nil
            }
    }

    static func property(_ value: Tweak.Value) -> CFPropertyList {
        switch value {
        case .boolean(let flag): flag as CFBoolean
        case .number(let number): number as CFNumber
        case .text(let text): text as CFString
        }
    }

    /// Returns whether `current` counts as `wanted`. cfprefsd returns whatever type was written, so the number
    /// `1` counts as `true` and `0` as `false`.
    static func matches(_ current: CFPropertyList, _ wanted: Tweak.Value) -> Bool {
        switch wanted {
        case .boolean(let flag):
            // `defaults write` with no type flag stores a string, and `UserDefaults.bool(forKey:)` still reads
            // "YES" and "1" as true.
            if let text = current as? NSString { return text.boolValue == flag }
            guard let number = current as? NSNumber else { return false }
            return number.boolValue == flag
        case .number(let expected):
            guard let number = current as? NSNumber else { return false }
            return abs(number.doubleValue - expected) < 0.0001
        case .text(let expected):
            return (current as? String) == expected
        }
    }
}

public enum TweakRestart {
    /// Quits the system process that owns a setting, with `killall`. macOS starts it again at once, and it reads
    /// the setting as it starts. This needs no administrator rights.
    @concurrent
    public static func run(_ restart: Tweak.Restart) async {
        let name: String
        switch restart {
        case .dock: name = "Dock"
        case .finder: name = "Finder"
        case .controlCenter: name = "ControlCenter"
        case .windowManager: name = "WindowManager"
        case .none, .relaunchApps, .logOut, .terminalQuits: return
        }
        _ = await Subprocess.run("/usr/bin/killall", [name], timeout: 10)
    }
}
