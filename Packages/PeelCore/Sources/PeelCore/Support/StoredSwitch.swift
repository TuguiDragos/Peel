public import Foundation

public extension UserDefaults {
    /// A switch as SwiftUI's `AppStorage` reads it: `whenNeverSet` until a value is stored, then what `bool(forKey:)`
    /// makes of that value, so one given as text, such as a launch argument's `NO`, reads as the switch shows it.
    func isOn(_ key: String, whenNeverSet: Bool) -> Bool {
        object(forKey: key) == nil ? whenNeverSet : bool(forKey: key)
    }
}
