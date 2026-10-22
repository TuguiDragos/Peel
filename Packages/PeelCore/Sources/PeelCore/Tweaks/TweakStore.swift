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
        let layers = layers(of: tweak)
        // A managed value comes before every layer, and only the "App" functions read it.
        guard let current = isManaged ? Self.copy(key, from: tweak.domain) : layers.inEffect else {
            return TweakState(isOn: false, isManaged: isManaged, text: nil)
        }

        let isOn: Bool
        var text: String?
        switch tweak.kind {
        case .aSwitch(let wanted), .aSwitchForThisAppAlone(let wanted):
            isOn = Self.matches(current, wanted)
        case .folder, .name:
            text = current as? String
            isOn = text?.isEmpty == false
        }
        let elsewhere = isManaged ? nil : Self.heldElsewhere(of: tweak.kind, isOn: isOn, in: layers)
        return TweakState(isOn: isOn, isManaged: isManaged, text: text, heldElsewhere: elsewhere)
    }

    /// What each layer macOS searches holds for a key, in Apple's order ("Preference Domains"): this Mac alone, the
    /// person's own (Peel's), the person's global domain, then every account's, for the app and for every app.
    struct Layers {
        var thisMac: CFPropertyList?
        var own: CFPropertyList?
        var everyAccount: CFPropertyList?
        /// The person's own global domain.
        var everyApp: CFPropertyList?
        var everyAccountForEveryApp: CFPropertyList?

        var inEffect: CFPropertyList? { thisMac ?? own ?? everyApp ?? everyAccount ?? everyAccountForEveryApp }
    }

    private func layers(of tweak: Tweak) -> Layers {
        let key = tweak.key as CFString
        let domain = Self.domain(tweak.domain)
        func value(_ user: CFString, _ host: CFString, in domain: CFString) -> CFPropertyList? {
            CFPreferencesCopyValue(key, domain, user, host)
        }
        var layers = Layers(
            thisMac: value(kCFPreferencesCurrentUser, kCFPreferencesCurrentHost, in: domain),
            own: value(kCFPreferencesCurrentUser, kCFPreferencesAnyHost, in: domain)
        )
        // A switch for one app alone never reads past the person's own layers of that app.
        if case .aSwitchForThisAppAlone = tweak.kind { return layers }
        layers.everyAccount = value(kCFPreferencesAnyUser, kCFPreferencesCurrentHost, in: domain)
            ?? value(kCFPreferencesAnyUser, kCFPreferencesAnyHost, in: domain)
        if tweak.domain != Self.globalDomain {
            synchronizeOnce(Self.globalDomain)
            let global = kCFPreferencesAnyApplication
            layers.everyApp = value(kCFPreferencesCurrentUser, kCFPreferencesCurrentHost, in: global)
                ?? value(kCFPreferencesCurrentUser, kCFPreferencesAnyHost, in: global)
            layers.everyAccountForEveryApp = value(kCFPreferencesAnyUser, kCFPreferencesCurrentHost, in: global)
                ?? value(kCFPreferencesAnyUser, kCFPreferencesAnyHost, in: global)
        }
        return layers
    }

    /// Where a value Peel can't change from its own layer comes from: this Mac alone, which wins over Peel's, or, for a
    /// switch on with nothing of Peel's, the layer macOS falls back to, since removing Peel's key would change nothing.
    static func heldElsewhere(of kind: Tweak.Kind, isOn: Bool, in layers: Layers) -> TweakState.Elsewhere? {
        if layers.thisMac != nil { return .thisMac }
        guard layers.own == nil, case .aSwitch = kind, isOn else { return nil }
        if layers.everyApp != nil { return .everyApp }
        if layers.everyAccount != nil { return .everyAccount }
        return layers.everyAccountForEveryApp != nil ? .everyApp : nil
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
            ? CFPreferencesCopyValue(
                key,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
            : CFPreferencesCopyAppValue(key, name as CFString)
    }

    private static func copyStored(_ key: CFString, from name: String) -> CFPropertyList? {
        CFPreferencesCopyValue(key, domain(name), kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static func set(_ key: CFString, to value: CFPropertyList?, in name: String) {
        if name == globalDomain {
            CFPreferencesSetValue(
                key,
                value,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            )
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
            // A number written as a string, as `defaults write` with no type flag stores it, counts as the number
            // it spells, which is how `UserDefaults.double(forKey:)` reads it.
            let number: Double? = switch current {
            case let text as NSString: Double(text.trimmingCharacters(in: .whitespaces))
            case let number as NSNumber: number.doubleValue
            default: nil
            }
            guard let number else { return false }
            return abs(number - expected) < 0.0001
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
