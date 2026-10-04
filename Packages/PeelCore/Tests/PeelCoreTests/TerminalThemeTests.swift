import AppKit
@testable import PeelCore
import Testing

struct TerminalThemeTests {
    static let clearDark = URL(filePath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Initial Settings/Clear Dark.terminal")
    static let ansiKeys = ["", "Bright"].flatMap { brightness in
        ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"].map { "ANSI\(brightness)\($0)Color" }
    }

    @Test func everyThemeIsTerminalsClearDarkWithItsOwnColors() throws {
        let apple = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: Self.clearDark), format: nil)
                as? [String: Any]
        )
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
            try Self.expectColors(of: theme, in: TerminalProfile.settings(for: theme))
        }
    }

    @Test func everyThemeInTheRepositoryIsWhatTheTerminalExportWrites() throws {
        let themes = TerminalThemeCatalog.all
        let folder = StringCatalogTests.repository.appending(path: "Terminal", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Themes").path)
        let renders = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "Renders").path)
        #expect(Set(files.filter { $0.hasSuffix(".terminal") }) == Set(themes.map { "\($0.profileName).terminal" }))
        #expect(Set(renders.filter { $0.hasSuffix(".png") }) == Set(themes.map { "\($0.name).png" }))
        let page = try String(contentsOf: StringCatalogTests.repository.appending(path: "TERMINAL.md"), encoding: .utf8)
        for theme in themes {
            let data = try Data(contentsOf: folder.appending(path: "Themes/\(theme.profileName).terminal"))
            let published = try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let profile = try TerminalProfile.settings(for: theme)
            #expect(Set(published.keys) == Set(profile.keys), "\(theme.name)")
            for (key, value) in profile where !key.hasSuffix("Color") {
                #expect((published[key] as? NSObject)?.isEqual(value) == true, "\(theme.name): \(key)")
            }
            try Self.expectColors(of: theme, in: published)
            #expect(page.contains("Terminal/Themes/\(theme.profileName.replacing(" ", with: "%20")).terminal"), "\(theme.name)")
            #expect(page.contains("Terminal/Renders/\(theme.name.replacing(" ", with: "%20")).png"), "\(theme.name)")
        }
    }

    @Test func terminalMDShowsEveryLinePeelWritesAndEveryPromptAndTool() throws {
        let page = try String(contentsOf: StringCatalogTests.repository.appending(path: "TERMINAL.md"), encoding: .utf8)
        let folder = StringCatalogTests.repository.appending(path: "Terminal/Prompts", directoryHint: .isDirectory)
        let pictures = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".png") }
        #expect(Set(pictures) == Set(PromptStyle.allCases.map { "\($0).png" }))
        let homebrew = URL(filePath: "/opt/homebrew", directoryHint: .isDirectory)
        var lines =
            ShellSetting.allCases.flatMap(\.lines) + [ShellFile.completionSystem]
            + PromptStyle.allCases.flatMap(\.lines)
        lines += GitSetting.allCases.filter { $0 != .signCommits }.flatMap { $0.values(signingKey: nil) }.map { "git config --global \($0.key) \($0.value)" }
        lines += ["git config --global gpg.format ssh", "git config --global commit.gpgSign true"]
        lines += SSHSetting.allCases.flatMap(\.lines)
        lines += TerminalTool.allCases.flatMap { $0.setup(prefix: homebrew) }.flatMap(\.lines).map {
            $0.replacing("/opt/homebrew", with: "$HOMEBREW_PREFIX")
        }
        let pageLines = Set(page.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        for line in lines {
            #expect(pageLines.contains(line), "\(line)")
        }
        for tool in TerminalTool.allCases {
            #expect(page.contains("`\(tool.installCommand)`"), "\(tool)")
        }
        for style in PromptStyle.allCases {
            #expect(page.contains("Terminal/Prompts/\(style).png"), "\(style)")
        }
    }

    static func expectColors(of theme: TerminalTheme, in profile: [String: Any]) throws {
        let colors = [
            ("BackgroundColor", theme.background), ("TextColor", theme.text), ("TextBoldColor", theme.text),
            ("CursorColor", theme.cursor), ("SelectionColor", theme.selection),
        ] + zip(ansiKeys, theme.ansi)
        for (key, expected) in colors {
            let data = try #require(profile[key] as? Data, "\(theme.name): \(key)")
            let color = try #require(
                try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)?.usingColorSpace(.sRGB)
            )
            let channels = [color.redComponent, color.greenComponent, color.blueComponent].map {
                Int(($0 * 255).rounded())
            }
            #expect(channels == [Int(expected >> 16 & 0xFF), Int(expected >> 8 & 0xFF), Int(expected & 0xFF)], "\(theme.name): \(key)")
            #expect(color.alphaComponent == (key == "BackgroundColor" ? 0.95 : 1), "\(theme.name): \(key)")
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
