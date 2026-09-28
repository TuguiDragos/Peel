import Foundation

enum PreferenceFile {
    /// True for a preference file whose bytes can be read and are not a property list: nothing can read the settings
    /// in it, the app included.
    static func isDamaged(_ url: URL) -> Bool {
        guard url.pathExtension == "plist", let data = BoundedRead.data(at: url) else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
    }
}
