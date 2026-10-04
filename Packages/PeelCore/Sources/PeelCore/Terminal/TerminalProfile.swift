import AppKit

public enum TerminalProfile {
    public static func settings(for theme: TerminalTheme) throws -> [String: Any] {
        var settings: [String: Any] = [
            "name": theme.profileName,
            "type": "Window Settings",
            "ProfileCurrentVersion": 2.09,
            "BackgroundColor": try archive(theme.background, alpha: 0.95),
            "BackgroundBlur": 0.5,
            "BackgroundBlurInactive": 0.0,
            "BackgroundSettingsForInactiveWindows": true,
            "TextColor": try archive(theme.text),
            "TextBoldColor": try archive(theme.text),
            "CursorColor": try archive(theme.cursor),
            "SelectionColor": try archive(theme.selection),
            "Font": font(),
            "FontAntialias": true,
            "FontHeightSpacing": 1.0,
            "FontWidthSpacing": 1,
            "DynamicANSIForegroundColors": false,
            "columnCount": 120,
            "rowCount": 30,
        ]
        for (index, color) in theme.ansi.enumerated() {
            settings["ANSI\(index < 8 ? "" : "Bright")\(ansiNames[index % 8])Color"] = try archive(color)
        }
        return settings
    }

    private static let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    private static func archive(_ color: UInt32, alpha: CGFloat = 1) throws -> Data {
        let sRGB = NSColor(
            srgbRed: CGFloat(color >> 16 & 0xFF) / 255,
            green: CGFloat(color >> 8 & 0xFF) / 255,
            blue: CGFloat(color & 0xFF) / 255,
            alpha: alpha
        )
        return try NSKeyedArchiver.archivedData(withRootObject: sRGB, requiringSecureCoding: true)
    }

    private static func font() -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName("NSFont", for: TerminalFont.self)
        archiver.encode(TerminalFont(), forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}

final class TerminalFont: NSObject, NSSecureCoding {
    static let supportsSecureCoding = true

    override init() {}

    required init?(coder: NSCoder) {
        nil
    }

    func encode(with coder: NSCoder) {
        coder.encode("SFMonoTerminal-Regular", forKey: "NSName")
        coder.encode(12.0, forKey: "NSSize")
        coder.encode(Int32(16), forKey: "NSfFlags")
    }
}
