import AppKit
import PeelCore
import SwiftUI
import UniformTypeIdentifiers

/// An app's or a file's own icon. Smart Invert leaves it as it is, as it leaves photos, because it shows the
/// item itself rather than a color Peel chose.
struct AppIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: IconCache.icon(for: url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .accessibilityIgnoresInvertColors()
            .accessibilityHidden(true)
    }
}

/// Tells what draws an icon that macOS now draws them differently. The icon style in System Settings > Appearance
/// changes every app's icon while Peel runs, and an image made earlier keeps the old one. macOS announces no change, so
/// this follows the settings it keeps the style in.
@Observable
final class IconStyle: NSObject {
    static let shared = IconStyle(defaults: .standard)

    /// The style itself, and the accent color, which a tinted style takes.
    private static let keys = ["AppleIconAppearanceTheme", "AppleAccentColor"]

    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
        for key in Self.keys { defaults.addObserver(self, forKeyPath: key, context: nil) }
    }

    isolated deinit {
        for key in Self.keys { defaults.removeObserver(self, forKeyPath: key) }
    }

    nonisolated override func observeValue(
        forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in self.changed() }
    }

    private func changed() {
        IconCache.forgetAll()
        revision += 1
    }
}

/// Tells what draws an icon that icons built away from the main thread have arrived, once for all that arrive in one
/// turn of the main run loop.
@Observable
final class IconArrivals {
    static let shared = IconArrivals()

    private(set) var count = 0
    @ObservationIgnored private var isTelling = false

    func arrived() {
        guard !isTelling else { return }
        isTelling = true
        Task {
            isTelling = false
            count += 1
        }
    }
}

/// The icons rows draw, so a list scrolled quickly doesn't build them again. An app's icon is read from its bundle,
/// which can be on a disk that doesn't answer, so it is built away from the main thread and the row shows `anyApp`
/// until it arrives. A file's icon is built in its row, so `NSCache` may let it go.
enum IconCache {
    /// `AppInspector` asks IconServices only about an app Launch Services knows.
    nonisolated private static let apps = AppIconStore(
        make: { AppInspector.icon(ofAppAt: $0) }, arrived: { IconArrivals.shared.arrived() }
    )
    /// "You can add, remove, and query items in the cache from different threads" (`NSCache.h`).
    nonisolated(unsafe) private static let files: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }()

    /// What a row shows for an app until its own icon is built.
    @MainActor static let anyApp = NSWorkspace.shared.icon(for: .applicationBundle)

    @MainActor
    static func icon(for url: URL) -> NSImage {
        _ = IconStyle.shared.revision
        guard url.isNamedAsAnApp else {
            let path = url.path(percentEncoded: false)
            if let image = files.object(forKey: path as NSString) { return image }
            let image = NSWorkspace.shared.icon(forFile: path)
            files.setObject(image, forKey: path as NSString)
            return image
        }
        _ = IconArrivals.shared.count
        return apps.icon(for: url) ?? anyApp
    }

    /// Builds the icons a list shows before it scrolls, and keeps them until they are forgotten.
    @concurrent
    static func warm(_ urls: [URL]) async {
        await apps.keep(urls.filter(\.isNamedAsAnApp))
    }

    @MainActor
    static func forgetAll() {
        apps.forgetAll()
        files.removeAllObjects()
    }

    /// Icons are held by path, so once what was at a path is removed or replaced, its icon is let go.
    @MainActor
    static func forget(_ urls: some Sequence<URL>) {
        let urls = Array(urls)
        apps.forget(urls)
        for url in urls where !url.isNamedAsAnApp {
            files.removeObject(forKey: url.path(percentEncoded: false) as NSString)
        }
    }
}
