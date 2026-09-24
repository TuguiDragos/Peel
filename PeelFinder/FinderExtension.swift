import AppKit
import FinderSync

final class FinderExtension: FIFinderSync {
    override init() {
        super.init()
        // Finder reports selected items only inside the watched folders, and an app can be anywhere.
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/", directoryHint: .isDirectory)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems, selectedApplication != nil else { return nil }
        let menu = NSMenu(title: "")
        let item = menu.addItem(withTitle: String(localized: "Uninstall with Peel…"), action: #selector(openInPeel(_:)), keyEquivalent: "")
        item.image = NSImage(resource: .peelGlyph)
        // On macOS 27 and later, AppKit usually hides menu item images. The glyph marks this item as Peel's in
        // Finder's menu, so the item asks for its image to be shown.
        if #available(macOS 27, *) {
            item.preferredImageVisibility = .visible
        }
        return menu
    }

    @objc private func openInPeel(_ sender: NSMenuItem) {
        guard let application = selectedApplication, var components = URLComponents(string: "peel://open") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: application.path(percentEncoded: false))]
        guard let url = components.url else { return }
        // Opens the URL in the copy of Peel that contains this extension. Launch Services might send `peel://`
        // URLs to a different copy of Peel.
        guard let host = hostApplication else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The app that contains this extension, or `nil` when the extension is not inside an app.
    /// It is three levels up: `Peel.app/Contents/PlugIns/PeelFinder.appex`.
    private var hostApplication: URL? {
        let host = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return host.pathExtension == "app" ? host : nil
    }

    private var selectedApplication: URL? {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), items.count == 1, items[0].pathExtension == "app" else {
            return nil
        }
        return items[0]
    }
}
