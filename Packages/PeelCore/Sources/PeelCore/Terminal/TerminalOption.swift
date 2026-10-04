import Foundation

public enum TerminalOption: String, CaseIterable, Sendable {
    case optionAsMeta = "useOptionAsMetaKey"
    case noAlertSound = "Bell"

    private var valueWhenOn: Bool {
        switch self {
        case .optionAsMeta: true
        case .noAlertSound: false
        }
    }

    func isOn(in profile: [String: Any]) -> Bool {
        (profile[rawValue] as? NSNumber)?.boolValue == valueWhenOn
    }

    func set(_ isOn: Bool, in profile: inout [String: Any]) {
        profile[rawValue] = isOn ? valueWhenOn : nil
    }
}
