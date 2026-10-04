import AppKit
@testable import PeelCore
import Testing

struct TerminalThemeTests {
    static let clearDark = URL(filePath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Clear Dark.terminal")
    static let ansiKeys = ["", "Bright"].flatMap { brightness in
        ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"].map { "ANSI\(brightness)\($0)Color" }
    }

    @Test func everyThemeIsTerminalsClearDarkWithItsOwnColors() throws {
        let apple = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: Self.clearDark), format: nil) as? [String: Any])
        for theme in TerminalThemeCatalog.all {
            let profile = try TerminalProfile.settings(for: theme)
            #expect(Set(profile.keys) == Set(apple.keys).union(["CursorColor"]), "\(theme.name)")
            for (key, value) in apple where !key.hasSuffix("Color") && key != "name" {
                #expect((profile[key] as? NSObject)?.isEqual(value) == true, "\(theme.name): \(key)")
            }
            #expect(profile["name"] as? String == theme.profileName)
        }
    }

    @Test func everyColorShowsInTerminalAsTheThemeDefinesIt() throws {
        for theme in TerminalThemeCatalog.all {
            let profile = try TerminalProfile.settings(for: theme)
            let colors = [
                ("BackgroundColor", theme.background), ("TextColor", theme.text), ("TextBoldColor", theme.text),
                ("CursorColor", theme.cursor), ("SelectionColor", theme.selection),
            ] + zip(Self.ansiKeys, theme.ansi)
            for (key, expected) in colors {
                let data = try #require(profile[key] as? Data, "\(theme.name): \(key)")
                let color = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)?.usingColorSpace(.sRGB))
                let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
                #expect(channels == [Int(expected >> 16 & 0xFF), Int(expected >> 8 & 0xFF), Int(expected & 0xFF)], "\(theme.name): \(key)")
                #expect(color.alphaComponent == (key == "BackgroundColor" ? 0.95 : 1), "\(theme.name): \(key)")
            }
        }
    }

    @Test func everyThemePassesTheContrastAudit() {
        for theme in TerminalThemeCatalog.all {
            let issues = TerminalThemeAudit.issues(of: theme)
            #expect(issues.isEmpty, "\(theme.name): \(issues.joined(separator: "; "))")
        }
    }

    @Test func everyThemeLooksUnlikeTheOthers() {
        let themes = TerminalThemeCatalog.all
        for (index, theme) in themes.enumerated() {
            for other in themes[(index + 1)...] {
                #expect(TerminalThemeAudit.meanDifference(theme, other) >= 5, "\(theme.name) and \(other.name)")
            }
        }
    }

    @Test func everyThemeHasItsOwnNameAndSixteenColors() {
        let names = TerminalThemeCatalog.all.map(\.name)
        #expect(Set(names).count == names.count)
        for theme in TerminalThemeCatalog.all {
            #expect(!theme.name.isEmpty)
            #expect(theme.ansi.count == 16, "\(theme.name)")
        }
    }
}
