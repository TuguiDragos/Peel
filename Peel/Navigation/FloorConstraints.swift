import AppKit

/// Holds the main window at its floor on macOS 27, through required constraints on its content view, which AppKit
/// keeps on every resize. A SwiftUI minimum around the columns makes SwiftUI 27 lay them out wider than the window
/// while the sidebar slides back: the page runs past the window's edge and toolbar items move into the overflow menu.
@MainActor
final class FloorConstraints {
    private var constraints: [NSLayoutConstraint] = []

    func hold(_ floor: CGSize, in window: NSWindow) {
        guard let content = window.contentView else { return }
        if constraints.first?.firstItem !== content {
            NSLayoutConstraint.deactivate(constraints)
            constraints = [
                content.widthAnchor.constraint(greaterThanOrEqualToConstant: floor.width),
                content.heightAnchor.constraint(greaterThanOrEqualToConstant: floor.height),
            ]
            NSLayoutConstraint.activate(constraints)
        }
        if constraints[0].constant != floor.width { constraints[0].constant = floor.width }
        if constraints[1].constant != floor.height { constraints[1].constant = floor.height }
    }
}
