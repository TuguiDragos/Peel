import AppKit
import SwiftUI

#if DEBUG
/// Renders Home, About and the menu bar panel to PNG files in light and dark when `PEEL_SNAPSHOT` names a folder,
/// then quits. This lets their layouts be checked without a screenshot, in any language Peel runs in. Each view is
/// drawn at the width the app gives it, on the background it has there: About on its paper, the menu bar panel on
/// the paper it draws itself, and Home on the window's plain color, since `ImageRenderer` does not draw glass.
enum HomeSnapshot {
    static func runIfRequested() async {
        guard let directory = ProcessInfo.processInfo.environment["PEEL_SNAPSHOT"] else { return }
        let home = HomeModel()
        let helper = HelperModel()
        let stats = LifetimeStats()
        await home.refresh(helper: helper)
        await ExclusionsStore.shared.load()
        let window = Color(nsColor: .windowBackgroundColor)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            render(HomeContent().environment(home).environment(helper).environment(stats), width: 360, height: 760, on: window, scheme: scheme, to: "\(directory)/home-content-\(name).png")
            // Home again with Show Borders on, for this image only. The stickers then outline their edges.
            render(HomeContent().environment(home).environment(helper).environment(stats).environment(\._accessibilityShowButtonShapes, true), width: 360, height: 760, on: window, scheme: scheme, to: "\(directory)/home-content-borders-\(name).png")
            // The permissions at their widest, and at their narrowest, where Home puts its two halves side by side.
            render(HomePermissionsContent().environment(home).environment(helper).environment(ExclusionsStore.shared), width: 720, height: 680, on: window, scheme: scheme, to: "\(directory)/home-detail-\(name).png")
            render(HomePermissionsContent().environment(home).environment(helper).environment(ExclusionsStore.shared), width: 480, height: 700, on: window, scheme: scheme, to: "\(directory)/detail-narrow-\(name).png")
            render(AboutContent().fixedSize(horizontal: false, vertical: true), width: 380, on: Album.sheet, scheme: scheme, to: "\(directory)/about-\(name).png")
            render(MenuBarPanel().environment(AppLibrary()).environment(stats), width: 320, scheme: scheme, to: "\(directory)/menu-bar-\(name).png")
        }
        NSApp.terminate(nil)
    }

    /// Saves `view` as a PNG at `path`, `width` wide and `height` tall, or as tall as it needs when `height` is nil.
    private static func render(_ view: some View, width: CGFloat, height: CGFloat? = nil, on backdrop: Color = .clear, scheme: ColorScheme, to path: String) {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(backdrop).environment(\.colorScheme, scheme))
        renderer.scale = 2
        guard let image = renderer.nsImage, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
    }
}
#endif
