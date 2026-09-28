import AppKit
import SwiftUI

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

/// The icons rows draw. `NSWorkspace.icon(forFile:)` doesn't promise to cache and builds a new image each
/// time, and rows ask for icons in `body`, on the main thread, so a list scrolled quickly would build the same
/// icons again and again. `NSCache` holds them and lets them go when memory is short. Apps are held apart from
/// files, so a long list of files never pushes the apps' icons out.
enum IconCache {
    /// "You can add, remove, and query items in the cache from different threads" (`NSCache.h`).
    nonisolated(unsafe) private static let apps = cache()
    nonisolated(unsafe) private static let files = cache()

    nonisolated private static func cache() -> NSCache<NSString, NSImage> {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        return cache
    }

    nonisolated private static func images(for url: URL) -> NSCache<NSString, NSImage> {
        url.pathExtension.lowercased() == "app" ? apps : files
    }

    @MainActor
    static func icon(for url: URL) -> NSImage {
        let path = url.path(percentEncoded: false)
        if let image = images(for: url).object(forKey: path as NSString) { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        images(for: url).setObject(image, forKey: path as NSString)
        return image
    }

    /// Builds the icons not held yet away from the main thread, so a list finds them ready when it first
    /// scrolls. `icon(forFile:)` may be called from any thread (its documentation).
    @concurrent
    static func warm(_ urls: [URL]) async {
        for url in urls {
            let path = url.path(percentEncoded: false)
            guard images(for: url).object(forKey: path as NSString) == nil else { continue }
            images(for: url).setObject(NSWorkspace.shared.icon(forFile: path), forKey: path as NSString)
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
