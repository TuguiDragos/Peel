import AppKit
import FinderSync
import PeelLink

final class FinderExtension: FIFinderSync {
    override init() {
        super.init()
        // Finder tells the extension what is selected only inside the folders it watches (`selectedItemURLs` in
        // FinderSync.h). An app can sit anywhere, so the extension watches the whole disk.
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/", directoryHint: .isDirectory)]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        // Once Peel is moved or deleted this process can run on, with no image to show and no app to open.
        guard menuKind == .contextualMenuForItems, FileManager.default.fileExists(atPath: Bundle.main.bundlePath),
              selectedApplication != nil
        else { return nil }
        let menu = NSMenu(title: "")
        let item = menu.addItem(withTitle: String(localized: "Uninstall with Peel…"), action: #selector(openInPeel(_:)), keyEquivalent: "")
        item.image = NSImage(resource: .peelGlyph)
        // On macOS 27 and later, AppKit usually hides menu item images. The glyph marks this item as Peel's in
        // Finder's menu, so the item asks for its image to be shown.
        if #available(macOS 27, *) {
            item.image = Self.glyphInTheLabelColor()
            item.preferredImageVisibility = .visible
        }
        return menu
    }

    /// Peel's glyph drawn in the color of a menu's text. Finder draws an extension's image as it comes, so a template
    /// stays black, and on a dark menu it can hardly be seen.
    private static func glyphInTheLabelColor() -> NSImage? {
        let glyph = NSImage(resource: .peelGlyph)
        let pixels = { (points: CGFloat) in Int(points * 2) }
        guard let picture = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels(glyph.size.width), pixelsHigh: pixels(glyph.size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return glyph }
        picture.size = glyph.size
        guard let context = NSGraphicsContext(bitmapImageRep: picture) else { return glyph }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let bounds = NSRect(origin: .zero, size: glyph.size)
        glyph.draw(in: bounds)
        NSColor.labelColor.set()
        bounds.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: glyph.size)
        image.addRepresentation(picture)
        return image
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
