import AppKit
import FinderSync
import PeelLink

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
        guard
            let application = selectedApplication,
            let url = OpenRequest.link(toApplicationAt: application.path(percentEncoded: false))
        else { return }
        // Opens the URL in the copy of Peel that contains this extension. Launch Services might send `peel://`
        // URLs to a different copy of Peel.
        guard let host = OpenRequest.hostApplication(ofExtensionAt: Bundle.main.bundleURL) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration())
    }

    private var selectedApplication: URL? {
        FIFinderSyncController.default().selectedItemURLs().flatMap(OpenRequest.application(amongSelected:))
    }
}
