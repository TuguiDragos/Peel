import AppKit
import SwiftUI

struct AboutContent: View {
    /// The width About is laid out for, in its window and on its page in the main window alike, so a long line
    /// breaks the same way in both rather than running across the whole column.
    static let width: CGFloat = 380

    @Environment(\.colorScheme) private var colorScheme
    @Environment(PeelUpdater.self) private var updater

    var body: some View {
        VStack(spacing: 12) {
            // IconServices draws the icon for the current appearance, so `id(colorScheme)` builds a new image
            // when the appearance changes.
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 96, height: 96)
                .id(colorScheme)
                .accessibilityIgnoresInvertColors()
                // Hidden from VoiceOver, since the name under it says the same.
                .accessibilityHidden(true)
            Text(verbatim: "Peel")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Version \(AppVersion.display)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let version = updater.newerVersion {
                PeelUpdateNotice(version: version, install: updater.checkForUpdates)
            }
            Text(
                "Remove apps and what they leave behind, free up space, and fine-tune your Mac.",
                comment: "What Peel does, under its name in About: it uninstalls apps, frees disk space, and has Tweaks and a Terminal page."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            credits
        }
        .padding(32)
    }

    /// How far a credit link takes clicks beyond its text, above and below. It brings a callout line up to the
    /// HIG's smallest target of 20 points, and the same amount is taken back outside, so the spacing is unchanged.
    fileprivate static let creditReach = 3.0

    /// Opens the license file bundled with the app, so a copy passed on carries its own license. Falls back
    /// to a web address if the file is missing.
    private func open(license name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            let page = switch name {
            case "GPL-3.0": Links.license
            case "blobatar-LICENSE": Links.blobatar
            case "Sparkle-LICENSE": Links.sparkle
            default: Links.argumentParser
            }
            NSWorkspace.shared.open(page)
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var credits: some View {
        VStack(spacing: 6) {
            Link(destination: Links.author) {
                Text(verbatim: "Țugui Dragoș-Constantin")
                    .creditTarget()
            }
            .padding(.vertical, -Self.creditReach)
            // GPL 3 asks that the copyright, the absence of warranty, and the way to read the license travel
            // with the program. The copy that travels is the one inside this bundle.
            Button {
                open(license: "GPL-3.0")
            } label: {
                Text("GNU GPL, version 3 or later", comment: "The license's name. GNU GPL stays as it is.")
                    .creditTarget()
            }
            .buttonStyle(.link)
            .padding(.vertical, -Self.creditReach)
            Text(
                "Peel moves what it removes to the Trash, and History can put it back. As the GPL states, it comes with no warranty, to the extent the law allows.",
                comment: "Under the license's name. History is Peel's page of everything it moved to the Trash."
            )
            .multilineTextAlignment(.center)
            // Apache 2.0 asks that the notice travel with anything that ships the code, and the `peel` command does.
            // One sentence with the link inside, so a language can put it where its grammar wants it.
            Text("The peel command uses [swift-argument-parser](peel-license:swift-argument-parser-LICENSE)", comment: "Keep the link as it is.")
            // MIT asks the same of any substantial part of blobatar's code, and the face's motion is ported from it.
            Text(
                "The face’s motion is adapted from [blobatar](peel-license:blobatar-LICENSE)",
                comment: "The face is Peel’s logo with eyes, at the head of the sidebar. Keep the link as it is."
            )
            Text(
                "Peel updates itself with [Sparkle](peel-license:Sparkle-LICENSE)",
                comment: "Sparkle is the open source framework that installs Peel’s updates. Keep the link as it is."
            )
            Link(destination: Links.repository) {
                Text(verbatim: "github.com/TuguiDragos/Peel")
                    .creditTarget()
            }
            .accessibilityLabel(Text(
                "Peel on GitHub, github.com/TuguiDragos/Peel",
                comment: "What VoiceOver reads for the link to Peel's source code. Keep the address as it is."
            ))
            .padding(.vertical, -Self.creditReach)
            .padding(.top, 8)
            Text(verbatim: "© 2026")
                .padding(.top, 10)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
        // A link inside a sentence that names a license opens the copy inside the app. Every other link opens as usual.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "peel-license" else { return .systemAction }
            open(license: url.absoluteString.replacingOccurrences(of: "peel-license:", with: ""))
            return .handled
        })
    }
}

/// A newer Peel than this copy. Sparkle's window shows what is new in it and installs it when the person chooses.
private struct PeelUpdateNotice: View {
    let version: String
    let install: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Version \(version) is out.")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(Album.orangeInk)
            Button("Install Update\u{2026}", action: install)
                .buttonStyle(StickerButtonStyle(fill: Album.orange, size: 12, ink: Album.onOrange))
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}

fileprivate extension View {
    func creditTarget() -> some View {
        padding(.vertical, AboutContent.creditReach)
            .contentShape(.rect)
    }
}

/// The About window: a fixed width, and as tall as its text needs in the current language.
struct AboutView: View {
    static let windowID = "about"
    /// The window's title, which VoiceOver also reads for the sidebar button that leads to About. It has its
    /// own key because the menu item's translations follow SwiftUI's words for About, which Polish writes "Peel…".
    static let title = LocalizedStringResource("About Peel (window)", defaultValue: "About Peel")

    var body: some View {
        AboutContent()
            .frame(width: AboutContent.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Album.sheet)
    }
}
