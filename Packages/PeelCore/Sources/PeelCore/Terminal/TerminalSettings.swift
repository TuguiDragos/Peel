import AppKit

public struct TerminalSettings: TerminalSettingsStoring, Sendable {
    public static let identifier = "com.apple.Terminal"
    private static let profilesKey = "Window Settings"
    private static let shellKey = "Shell"

    public init() {}

    public var isTerminalOpen: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.identifier).contains { !$0.isTerminated }
    }

    public var isManaged: Bool {
        ([Self.profilesKey] + TerminalProfileRole.allCases.map(\.rawValue)).contains {
            CFPreferencesAppValueIsForced($0 as CFString, Self.identifier as CFString)
        }
    }

    public func profiles() -> [String: [String: Any]] {
        CFPreferencesAppSynchronize(Self.identifier as CFString)
        return CFPreferencesCopyAppValue(Self.profilesKey as CFString, Self.identifier as CFString)
            as? [String: [String: Any]] ?? [:]
    }

    public func setProfiles(_ profiles: [String: [String: Any]]) -> Bool {
        CFPreferencesSetAppValue(Self.profilesKey as CFString, profiles as CFDictionary, Self.identifier as CFString)
        return CFPreferencesAppSynchronize(Self.identifier as CFString)
    }

    public func shell() -> String? {
        CFPreferencesAppSynchronize(Self.identifier as CFString)
        return CFPreferencesCopyAppValue(Self.shellKey as CFString, Self.identifier as CFString) as? String
    }

    public func profileName(for role: TerminalProfileRole) -> String? {
        CFPreferencesAppSynchronize(Self.identifier as CFString)
        return CFPreferencesCopyAppValue(role.rawValue as CFString, Self.identifier as CFString) as? String
    }

    public func setProfileName(_ name: String?, for role: TerminalProfileRole) -> Bool {
        CFPreferencesSetAppValue(role.rawValue as CFString, name as CFString?, Self.identifier as CFString)
        return CFPreferencesAppSynchronize(Self.identifier as CFString)
    }
}
