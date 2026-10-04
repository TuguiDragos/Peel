import Foundation

public enum ScreenshotName {
    public enum Problem: Sendable, Equatable {
        case separator
        case hidden
        case tooLong
    }

    static let longestName = 200

    public static func problem(with name: String) -> Problem? {
        if name.contains("/") || name.contains(":") { return .separator }
        if name.hasPrefix(".") { return .hidden }
        if name.utf8.count > longestName { return .tooLong }
        return nil
    }

    public static var macOSDefault: String? {
        Bundle(path: "/System/Library/CoreServices/screencaptureui.app")?
            .localizedString(forKey: "Screenshot", value: nil, table: "Localizable")
    }
}
