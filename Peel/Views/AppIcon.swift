import AppKit
import PeelCore
import SwiftUI
import Synchronization
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

/// The icons rows draw. `NSWorkspace.icon(forFile:)` doesn't promise to cache and builds a new image each
/// time, and rows ask for icons in `body`, on the main thread, so a list scrolled quickly would build the same
/// icons again and again. `NSCache` holds them and lets them go when memory is short. Apps are held apart from
/// files, so a long list of files never pushes the apps' icons out.
enum IconCache {
    /// "You can add, remove, and query items in the cache from different threads" (`NSCache.h`).
    nonisolated(unsafe) private static let apps = cache()
    nonisolated(unsafe) private static let files = cache()
    /// Counts the times every icon was let go, so an icon built before one is never kept after it.
    nonisolated private static let forgotten = Mutex(0)

    nonisolated private static func cache() -> NSCache<NSString, NSImage> {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }

    nonisolated private static func images(for url: URL) -> NSCache<NSString, NSImage> {
        url.isNamedAsAnApp ? apps : files
    }

    /// An app's icon is asked of `AppInspector`, which asks IconServices only about an app Launch Services knows.
    nonisolated private static func image(for url: URL) -> NSImage {
        url.isNamedAsAnApp
            ? AppInspector.icon(ofAppAt: url) : NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    /// What a row shows for an app until its own icon is built.
    @MainActor static let anyApp = NSWorkspace.shared.icon(for: .applicationBundle)
    @MainActor private static var building: Set<String> = []

    /// An app's own icon is read from its bundle, which can be on a disk that doesn't answer, so one not built yet is
    /// built away from the main thread, and the row shows `anyApp` until it arrives.
    @MainActor
    static func icon(for url: URL) -> NSImage {
        _ = IconStyle.shared.revision
        _ = IconArrivals.shared.count
        let path = url.path(percentEncoded: false)
        if let image = images(for: url).object(forKey: path as NSString) { return image }
        guard url.isNamedAsAnApp else {
            let image = image(for: url)
            images(for: url).setObject(image, forKey: path as NSString)
            return image
        }
        if building.insert(path).inserted {
            Task {
                await warm([url])
                building.remove(path)
                IconArrivals.shared.arrived()
            }
        }
        return anyApp
    }

    /// Builds the icons not held yet away from the main thread, so a list finds them ready when it first
    /// scrolls. `icon(forFile:)` may be called from any thread (its documentation).
    @concurrent
    static func warm(_ urls: [URL]) async {
        let generation = forgotten.withLock { $0 }
        for url in urls {
            let path = url.path(percentEncoded: false)
            guard images(for: url).object(forKey: path as NSString) == nil else { continue }
            let image = image(for: url)
            let isCurrent = forgotten.withLock { forgotten in
                guard forgotten == generation else { return false }
                images(for: url).setObject(image, forKey: path as NSString)
                return true
            }
            guard isCurrent else { return }
        }
    }

    @MainActor
    static func forgetAll() {
        forgotten.withLock { forgotten in
            forgotten += 1
            apps.removeAllObjects()
            files.removeAllObjects()
        }
    }

    /// Icons are held by path, so once what was at a path is removed or replaced, its icon is let go.
    @MainActor
    static func forget(_ urls: some Sequence<URL>) {
        for url in urls {
            images(for: url).removeObject(forKey: url.path(percentEncoded: false) as NSString)
        }
    }
}
