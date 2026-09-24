import SwiftUI

/// Peel's three animation speeds: `touch` for what responds to the pointer, `step` for a state that changes in
/// place, and `settle` for something that arrives and moves the layout around it. Use one of these rather than a
/// new duration, so that timing stays consistent across the app.
enum Motion {
    case touch
    case step
    case settle

    /// Whether an animated change moves something, or only changes it in place, such as its opacity, its color,
    /// or a number. Reduce Motion turns off `movement` only: Apple's accessibility guidance asks for fades in
    /// place of movement, not for no animation at all.
    enum Kind {
        case fade
        case movement
    }

    var duration: Double {
        switch self {
        case .touch: 0.12
        case .step: 0.22
        case .settle: 0.32
        }
    }

    var animation: Animation {
        .smooth(duration: duration)
    }
}

extension View {
    func motion(_ speed: Motion = .step, _ kind: Motion.Kind = .fade, value: some Equatable) -> some View {
        modifier(MotionModifier(speed: speed, kind: kind, value: value))
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let speed: Motion
    let kind: Motion.Kind
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion && kind == .movement ? nil : speed.animation, value: value)
    }
}
