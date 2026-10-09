import AppKit
import PeelCore
import SwiftUI

#if DEBUG
enum TerminalExport {
    static let directory = ProcessInfo.processInfo.environment["PEEL_TERMINAL_EXPORT"]

    static func runIfRequested() {
        guard let directory else { return }
        let themes = URL(filePath: directory).appending(path: "Themes", directoryHint: .isDirectory)
        let renders = URL(filePath: directory).appending(path: "Renders", directoryHint: .isDirectory)
        let prompts = URL(filePath: directory).appending(path: "Prompts", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: prompts, withIntermediateDirectories: true)
            for theme in TerminalThemeCatalog.all {
                let profile = try PropertyListSerialization.data(
                    fromPropertyList: TerminalProfile.settings(for: theme),
                    format: .xml,
                    options: 0
                )
                try profile.write(to: themes.appending(path: "\(theme.profileName).terminal"))
                try render(TerminalSession(theme: theme).frame(width: 300), to: renders.appending(path: "\(theme.name).png"))
            }
            let theme = TerminalThemeCatalog.all.first { $0.name == "Hadal" }
            let pictured = [
                ("folder", Prompt()), ("path", Prompt(start: .path)), ("nameAndFolder", Prompt(start: .nameAndFolder)),
                ("ownLine", Prompt(isOnItsOwnLine: true)),
            ]
            for (name, prompt) in pictured {
                let preview = PromptPreview(prompt: prompt, theme: theme, user: "you", host: "Mac").frame(width: 320)
                try render(preview, to: prompts.appending(path: "\(name).png"))
            }
        } catch {
            print("Terminal export failed: \(error)")
        }
        NSApp.terminate(nil)
    }

    private static func render(_ view: some View, to url: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 4
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
#endif
