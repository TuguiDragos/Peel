import AppKit
import PeelCore
import SwiftUI

/// Peel's logo with a face. Its motion is ported from blobatar (MIT, blobatar.dev): breathing, bobbing,
/// glancing, blinking, following the pointer, and a `happy` pose while the pointer is on the face. With the
/// pointer outside the window, it looks around by itself (`LookAround`), it smiles once when a removal
/// finishes (`Cheer`), and it is surprised once when a new version of Peel is out (`Surprise`).
struct PeelFace: View {
    var size: CGFloat

    @Environment(RemovalHistoryStore.self) private var history
    @Environment(AppLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets the face rest while no window is open. A closed window keeps its views, and no occlusion change
    /// reaches them, but the scene phase turns to `.background`, and back to active when the window returns.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        FaceLayers(size: size, isStill: reduceMotion, isSceneShown: scenePhase != .background)
            .frame(width: size, height: size)
            // It is the logo, so it opts out of color inversion to keep its orange rather than turn blue.
            .accessibilityIgnoresInvertColors()
            .accessibilityHidden(true)
            .onChange(of: history.justMoved) { _, moved in
                if moved != nil { Self.follow.cheer() }
            }
            .task(id: library.newerPeel?.version) {
                if let version = library.newerPeel?.version { Self.follow.surprise(for: version) }
            }
    }

    /// Where the face is looking. It is shared rather than kept in the view because the sidebar is rebuilt
    /// whenever the window switches between a whole page and three columns, and a new face would otherwise
    /// snap back to looking straight ahead.
    fileprivate static let follow = Follow()
}

private struct FaceLayers: NSViewRepresentable {
    let size: CGFloat
    let isStill: Bool
    let isSceneShown: Bool

    func makeNSView(context: Context) -> FaceLayerView {
        FaceLayerView(size: size)
    }

    func updateNSView(_ view: FaceLayerView, context: Context) {
        view.isStill = isStill
        view.isSceneShown = isSceneShown
    }
}

/// The face, drawn with Core Animation: a display link moves its layers each frame and touches nothing else.
/// Drawn by a SwiftUI `TimelineView` instead, every tick makes AppKit lay out the whole window, even when the
/// face sits in a hosting view of its own.
private final class FaceLayerView: NSView {
    let size: CGFloat
    var isStill = false {
        didSet { if isStill != oldValue { refresh() } }
    }
    var isSceneShown = true {
        didSet { if isSceneShown != oldValue { refresh() } }
    }

    /// Flipped so that y runs down from the top left, as in SwiftUI, which is how every position here is written.
    private let canvas = CALayer()
    private let head = CALayer()
    private let peel = CAShapeLayer()
    private let flap = CAShapeLayer()
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    /// The red dot of `Surprise`, beside the head rather than on it, so it stays put while the head moves.
    private let dot = CAShapeLayer()
    private var link: CADisplayLink?
    private var observers: [any NSObjectProtocol] = []
    private var pointerSeen: CGPoint?
    private var pointerMovedAt = -Double.infinity
    private var isQuick = false
    /// Decides whether a frame is worth sending. Each frame costs WindowServer about the same however little
    /// moved, so a frame goes out only once a corner of the head or an eye has moved a tenth of a pixel since the
    /// last frame sent.
    private var motion = VisibleMotion()

    init(size: CGFloat) {
        self.size = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        let square = CGRect(x: 0, y: 0, width: size, height: size)
        canvas.isGeometryFlipped = true
        canvas.frame = square
        head.bounds = square
        head.position = CGPoint(x: size / 2, y: size / 2)
        peel.frame = square
        peel.path = PeelBody().path(in: square).cgPath
        flap.frame = square
        flap.path = PeelFlap().path(in: square).cgPath
        flap.shadowPath = flap.path
        flap.shadowOpacity = 1
        flap.shadowRadius = 1.4 * size / 100
        flap.shadowOffset = CGSize(width: -0.7 * size / 100, height: 0.7 * size / 100)
        let eye = CGRect(x: 0, y: 0, width: Face.eye.width * size / 100, height: Face.eye.height * size / 100)
        for layer in eyes {
            layer.bounds = eye
            layer.path = Superellipse(n: 3).path(in: eye).cgPath
        }
        head.sublayers = [peel, flap] + eyes
        canvas.addSublayer(head)
        let dotSize = 2 * Face.dot.radius * size / 100
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.path = CGPath(ellipseIn: dot.bounds, transform: nil)
        dot.position = CGPoint(x: Face.dot.x * size / 100, y: Face.dot.y * size / 100)
        dot.isHidden = true
        canvas.addSublayer(dot)
        layer?.addSublayer(canvas)
        recolor()
        draw(at: CACurrentMediaTime())
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Takes no clicks, so they reach the control the face sits in.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else {
            link?.invalidate()
            link = nil
            return
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        refresh()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [canvas, head, peel, flap, dot] + eyes {
            layer.contentsScale = scale
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
    }

    /// Runs or pauses the display link, then draws the current frame. The face moves only while Reduce Motion
    /// is off, its window is open and at least partly visible, and Peel is the active app. Apple asks apps to
    /// stop unneeded work as soon as a window is hidden. While another app is active, the pointer the face
    /// follows is in that app. Visibility comes from occlusion, not from the window being key, so the face
    /// keeps moving while Settings or a sheet has the keyboard.
    private func refresh() {
        let isSeen = window?.occlusionState.contains(.visible) == true
        if !isStill, isSceneShown, isSeen, NSApp.isActive {
            if link == nil {
                let link = displayLink(target: self, selector: #selector(tick(_:)))
                link.preferredFrameRateRange = Self.calm
                link.add(to: .main, forMode: .common)
                self.link = link
            }
            link?.isPaused = false
        } else {
            link?.isPaused = true
        }
        draw(at: CACurrentMediaTime())
    }

    @objc private func tick(_ link: CADisplayLink) {
        draw(at: link.targetTimestamp)
    }

    /// The frame rate while no pointer is moving in the window. Breathing, blinking, and looking around are slow
    /// enough for 30 frames a second, and each frame costs about the same however little moves in it. A pointer
    /// moving in the window is followed at the display's full rate, and for half a second after, while the look
    /// settles on it, and so is the smile after a removal, from start to finish.
    private static let calm = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)

    private func draw(at time: CFTimeInterval) {
        let seen = pointer()
        if case .at(let point) = seen {
            if let last = pointerSeen, hypot(point.x - last.x, point.y - last.y) > 0.5 { pointerMovedAt = time }
            pointerSeen = point
        } else {
            pointerSeen = nil
        }
        let look = PeelFace.follow.step(toward: seen, at: time, still: isStill)
        let quick = time - pointerMovedAt < 0.5 || PeelFace.follow.isReacting
        if quick != isQuick {
            isQuick = quick
            link?.preferredFrameRateRange = quick ? .default : Self.calm
        }
        let pose = Pose(Idle(at: time * 1000, amplitude: isStill ? 0 : 1), look, size: size)
        guard motion.isWorthAFrame(pose.corners, pixelsPerPoint: Double(window?.backingScaleFactor ?? 2)) else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.transform = pose.head.transform
        head.position = pose.head.position
        for (eye, placed) in zip(eyes, pose.eyes) {
            eye.transform = placed.transform
            eye.position = placed.position
        }
        dot.isHidden = pose.dot <= 0
        dot.transform = CATransform3DMakeScale(max(pose.dot, 0.001), max(pose.dot, 0.001), 1)
        CATransaction.commit()
    }

    /// Resolves the face's colors from the asset catalog for the view's appearance. The eyes' `faceInk` has one
    /// value for every appearance, because the eyes always sit on orange.
    private func recolor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            peel.fillColor = NSColor(resource: .peelOrange).cgColor
            flap.fillColor = NSColor(resource: .peelCream).cgColor
            flap.shadowColor = NSColor(resource: .stickerShadow).cgColor
            dot.fillColor = NSColor.systemRed.cgColor
            for eye in eyes {
                eye.fillColor = NSColor(resource: .faceInk).cgColor
            }
        }
    }

    /// Where the pointer is, in the face's 100 by 100 square. It is sampled each frame rather than tracked,
    /// because a hover modifier on the window reports nothing over the columns of a split view.
    private func pointer() -> Pointer {
        guard let window else { return .unknown }
        guard window.isVisible, window.frame.contains(NSEvent.mouseLocation) else { return .away }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return .at(CGPoint(x: point.x / size * 100, y: (bounds.height - point.y) / size * 100))
    }
}

/// Where the head and the eyes go in one frame, worked out before anything moves, so that a frame that would
/// change nothing on the screen is never sent.
private struct Pose {
    struct Placed {
        var transform: CATransform3D
        var position: CGPoint
    }

    let size: CGFloat
    var head: Placed
    var eyes: [Placed] = []
    /// The size of `Surprise`'s dot, from 0 to 1.
    var dot: Double

    init(_ idle: Idle, _ look: Look, size: CGFloat) {
        self.size = size
        dot = look.dot
        let unit = size / 100
        // The head turns with the eyes, which is what keeps a glance readable at sidebar size.
        let turn = CGSize(width: look.aim.width * look.hold * Face.turn.x * unit,
                          height: look.aim.height * look.hold * Face.turn.y * unit)
        let rise = idle.bob * unit - 1.5 * look.lift * unit - look.startle * unit
        let lift = 1 + 0.04 * look.lift
        head = Placed(transform: CATransform3DMakeScale(idle.breathe.width, idle.breathe.height, 1)
                          .then(CATransform3DMakeRotation(look.aim.width * look.hold * Face.lean * .pi / 180, 0, 0, 1))
                          .then(CATransform3DMakeScale(lift, lift, 1)),
                      position: CGPoint(x: size / 2 + turn.width, y: size / 2 + turn.height + rise))

        let reach = Face.reach(toward: look.aim)
        let glance = CGSize(width: idle.glance.width * (1 - look.hold) + look.aim.width * reach * look.hold,
                            height: idle.glance.height * (1 - look.hold) + look.aim.height * reach * look.hold)
        let smile = Smile(amount: look.smile)
        // Foreshortening: turning narrows, flattens, and tilts the eyes, up to blobatar's peak values.
        let across = idle.wrap.across - 0.07 * abs(look.aim.width) * look.hold
        let down = idle.wrap.down - 0.046 * abs(look.aim.height) * look.hold
        let tilt = idle.wrap.tilt + 4.1 * look.aim.width * look.aim.height * look.hold
        for side in [-1.0, 1.0] {
            let scale = smile.scale(side)
            eyes.append(Placed(transform: CATransform3DMakeScale(1, min(idle.blink, look.openness), 1)
                                   .then(CATransform3DMakeScale(1 + look.widen, 1 + look.widen, 1))
                                   .then(CATransform3DMakeScale(1 + across + idle.wrap.leading * side, 1 + down, 1))
                                   .then(CATransform3DMakeRotation(tilt * side * .pi / 180, 0, 0, 1))
                                   .then(CATransform3DMakeScale(scale.width, scale.height, 1))
                                   .then(CATransform3DMakeRotation(smile.tilt(side) * .pi / 180, 0, 0, 1)),
                               position: CGPoint(x: (Face.center.x + side * Face.gap + glance.width
                                                     + smile.offset(side).width) * unit,
                                                 y: (Face.center.y + glance.height
                                                     + smile.offset(side).height) * unit)))
        }
    }

    /// The corners of the head and of each eye, on the canvas. Any way a layer can move (shifted, turned, grown,
    /// or squashed) moves at least one corner, so comparing corners catches every visible change.
    var corners: [SIMD2<Double>] {
        let turned = CATransform3DGetAffineTransform(head.transform)
        func onCanvas(_ point: CGPoint) -> SIMD2<Double> {
            let offset = CGPoint(x: point.x - size / 2, y: point.y - size / 2).applying(turned)
            return [head.position.x + offset.x, head.position.y + offset.y]
        }
        var points = [CGPoint(x: 0, y: 0), CGPoint(x: size, y: 0), CGPoint(x: size, y: size), CGPoint(x: 0, y: size)]
            .map(onCanvas)
        let half = CGSize(width: Face.eye.width * size / 200, height: Face.eye.height * size / 200)
        for eye in eyes {
            let shaped = CATransform3DGetAffineTransform(eye.transform)
            for corner in [CGPoint(x: -half.width, y: -half.height), CGPoint(x: half.width, y: -half.height),
                           CGPoint(x: half.width, y: half.height), CGPoint(x: -half.width, y: half.height)] {
                let offset = corner.applying(shaped)
                points.append(onCanvas(CGPoint(x: eye.position.x + offset.x, y: eye.position.y + offset.y)))
            }
        }
        let reach = Face.dot.radius * dot * size / 100
        let middle = SIMD2(Face.dot.x * size / 100, Face.dot.y * size / 100)
        points += [
            middle + [-reach, -reach], middle + [reach, -reach], middle + [reach, reach], middle + [-reach, reach],
        ]
        return points
    }
}

private extension CATransform3D {
    /// This transform, then `next`, in the order one SwiftUI modifier follows another.
    func then(_ next: CATransform3D) -> CATransform3D {
        CATransform3DConcat(self, next)
    }
}

/// Where the face is aimed, and how far into each reaction it is. `widen`, `startle`, `openness`, and `dot` are
/// `Surprise`'s: how much wider the eyes are, how far the head rises, in units, how open the eyes are, and the dot.
private struct Look {
    var aim = CGSize.zero
    var hold = 0.0
    var smile = 0.0
    var lift = 0.0
    var widen = 0.0
    var startle = 0.0
    var openness = 1.0
    var dot = 0.0
}

/// The face's look, stepped once a frame: blobatar's pursuit of the pointer, and its two reactions (a smile and
/// a lift) while the pointer is on the face, or while a finished removal's `Cheer` asks for them. With the
/// pointer outside the window, the look follows `LookAround`.
///
/// The aim eases toward its target with a time constant of `Face.settle`, and jumps to a target more than 1.6
/// away (blobatar's `SNAP`). Near the face's middle the aim eases back to center (blobatar's `DEADZONE`), so a
/// pointer right on the face gets a straight look rather than a squint.
private final class Follow {
    private var look = Look()
    private var smiling = 0.0
    private var lifting = 0.0
    private var holding = 0.0
    private var cheering: Cheer?
    private var surprising: Surprise?
    /// The version the face was last surprised by, so a face built again, or a version found again, does not
    /// surprise twice.
    private var surprisedBy: String?
    /// How long the smile takes to arrive, and to leave.
    private static let smileRise = 0.3
    private static let smileFall = 0.4
    /// The look-around under way while the pointer is outside the window, and how long it has run. Time is
    /// counted in steps rather than by the clock, so a face that was paused goes on from where it stopped.
    private var lookingAround: (plan: LookAround, elapsed: TimeInterval)?
    private var last: TimeInterval?
    /// How long a frame takes on the current display, learned from the frames themselves. Each step covers at
    /// most two frames, so when the main thread is held for a while (building a page, for example), the face
    /// carries on from where it was instead of jumping.
    private var frame = 1.0 / 60

    /// Smiles once, holding the smile for one `Motion.settle` once it has arrived.
    func cheer() {
        cheering = Cheer(rise: Self.smileRise, hold: Motion.settle.duration, fall: Self.smileFall)
    }

    /// Starts the surprise, once for each new version of Peel.
    func surprise(for version: String) {
        guard version != surprisedBy else { return }
        surprisedBy = version
        surprising = Surprise()
    }

    /// Whether a reaction is under way, which the face follows at the display's full frame rate.
    var isReacting: Bool { cheering != nil || surprising != nil }

    func step(toward seen: Pointer, at time: TimeInterval, still: Bool) -> Look {
        let elapsed = last.map { time - $0 } ?? 0
        last = time
        if elapsed > 0, elapsed < 0.1 { frame += (elapsed - frame) / 10 }
        let step = max(0, min(elapsed, 2 * frame))
        guard !still else {
            // Under Reduce Motion the face holds still, and a reaction it could not give is not given later.
            cheering = nil
            surprising = nil
            return Look()
        }
        let pointer: CGPoint?
        switch seen {
        case .unknown: return look
        case .away: pointer = nil
        case .at(let point): pointer = point
        }

        var target: CGSize
        var held: Double
        if let pointer {
            lookingAround = nil
            let toward = CGSize(width: pointer.x - Face.center.x, height: pointer.y - Face.center.y)
            let reach = hypot(toward.width, toward.height)
            let near = Self.smoothstep(min(1, reach / (Face.radius * 100 * 0.55)))
            target =
                reach > 0 ? CGSize(width: toward.width / reach * near, height: toward.height / reach * near) : .zero
            held = 1
        } else {
            let plan =
                lookingAround?.plan ?? LookAround(from: .init(aim: [look.aim.width, look.aim.height], hold: holding))
            let elapsed = (lookingAround?.elapsed ?? 0) + step
            lookingAround = (plan, elapsed)
            let moment = plan.moment(after: elapsed)
            target = CGSize(width: moment.aim.x, height: moment.aim.y)
            held = moment.hold
        }

        surprising?.advance(by: step)
        if surprising?.isOver == true { surprising = nil }
        // While the surprise looks at its dot, that is where the face looks, wherever the pointer is.
        if let surprising, surprising.look > 0 {
            target = CGSize(width: Surprise.aim.x, height: Surprise.aim.y)
            held = surprising.look
        }

        let pursuit = step > 0 ? 1 - exp(-step * 1000 / Face.settle) : 1
        let rate = hypot(target.width - look.aim.width, target.height - look.aim.height) > 1.6 ? 1 : pursuit
        look.aim = CGSize(width: look.aim.width + (target.width - look.aim.width) * rate,
                          height: look.aim.height + (target.height - look.aim.height) * rate)

        let onFace = pointer.map { hypot($0.x - 50, $0.y - 50) <= Face.radius * 100 } ?? false
        cheering?.advance(by: step)
        if cheering?.isOver == true { cheering = nil }
        let happy = onFace || cheering?.wantsHappyPose == true || surprising?.wantsHappyPose == true
        holding = Self.ramp(holding, to: held, by: step / 0.25)
        smiling = Self.ramp(smiling, to: happy ? 1 : 0, by: step / (happy ? Self.smileRise : Self.smileFall))
        lifting = Self.ramp(lifting, to: happy ? 1 : 0, by: step / (happy ? 0.22 : 0.16))

        look.hold = Curve.easeInOut(holding)
        look.smile = happy ? Curve.morph(smiling) : Curve.easeInOut(smiling)
        look.lift = Curve.lift(lifting)
        look.widen = surprising?.widen ?? 0
        look.startle = surprising?.rise ?? 0
        look.openness = surprising?.openness ?? 1
        look.dot = surprising?.dot ?? 0
        return look
    }

    private static func ramp(_ value: Double, to target: Double, by amount: Double) -> Double {
        value < target ? min(target, value + amount) : max(target, value - amount)
    }

    private static func smoothstep(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// What the face knows about the pointer. A rebuilt face has no window for its first frame, so the pointer is
/// `unknown` then, and the look stays as it was.
private enum Pointer {
    case unknown
    case away
    case at(CGPoint)
}

/// blobatar's `happy` pose, `amount` of the way in (0 to 1): eyes wide and flat, tilted, lifted, and spread apart.
private struct Smile {
    var amount = 0.0

    func scale(_ side: Double) -> CGSize {
        let right = side > 0 ? 1.0 : 0.0
        return CGSize(width: 1 + amount * (0.72 + right * 0.08), height: 1 - amount * (0.7 - right * 0.05))
    }

    func tilt(_ side: Double) -> Double { amount * (8 + (side > 0 ? -16 : 0)) * side }

    func offset(_ side: Double) -> CGSize { CGSize(width: amount * 1.5 * side, height: -amount * 1.5) }
}

/// One frame of the idle motion: breathing, bobbing, glancing (and how it changes the eyes' shape), and blinking.
private struct Idle {
    var breathe = CGSize(width: 1, height: 1)
    var bob = 0.0
    var glance = CGSize.zero
    var wrap = (across: 0.0, leading: 0.0, down: 0.0, tilt: 0.0)
    var blink = 1.0

    init(at milliseconds: Double, amplitude: Double) {
        guard amplitude > 0 else { return }
        let breath = Curve.easeInOut(Self.alternate(milliseconds, period: 2800))
        breathe = CGSize(width: 1 + 0.022 * amplitude * breath, height: 1 - 0.018 * amplitude * breath)
        bob = -1.1 * amplitude * Curve.easeInOut(Self.alternate(milliseconds, period: 3400))

        let glancing = Self.cycle(milliseconds, period: Self.glancePeriod)
        glance = CGSize(width: Self.stop(glancing, Self.fixations, 1) * Self.reach.x * amplitude,
                        height: Self.stop(glancing, Self.fixations, 2) * Self.reach.y * amplitude)
        wrap = (across: Self.stop(glancing, Self.shapes, 1) * Self.reach.x * amplitude,
                leading: Self.stop(glancing, Self.shapes, 2) * Self.reach.x * amplitude,
                down: Self.stop(glancing, Self.shapes, 3) * Self.reach.y * amplitude,
                tilt: Self.stop(glancing, Self.shapes, 4) * Self.reach.x * Self.reach.y * amplitude)

        let blinking = Self.cycle(milliseconds, period: Self.blinkPeriod)
        blink = switch blinking {
        case ..<0.972: 1
        case ..<0.986: 1 - 0.92 * amplitude * Curve.easeIn((blinking - 0.972) / 0.014)
        default: 1 - 0.92 * amplitude * (1 - Curve.easeOut((blinking - 0.986) / 0.014))
        }
    }

    /// The middle of blobatar's ranges. blobatar varies these per face so that a crowd of faces never moves in
    /// step, which one face does not need.
    private static let blinkPeriod = 5200.0
    private static let glancePeriod = 6100.0
    private static let reach = (x: 1.6, y: 1.2)

    /// Six fixations, each reached in a quick flick and then held: center, up left, right, down, up right, left.
    /// Each row is a point in the cycle (0 to 1), then x and y.
    private static let fixations: [[Double]] = [
        [0, 0, 0], [0.15, 0, 0],
        [0.165, -0.8, -0.9], [0.31, -0.8, -0.9],
        [0.325, 1, 0.1], [0.47, 1, 0.1],
        [0.485, -0.15, 0.85], [0.63, -0.15, 0.85],
        [0.645, 0.75, -0.8], [0.79, 0.75, -0.8],
        [0.805, -1, -0.15], [0.985, -1, -0.15],
        [1, 0, 0],
    ]

    /// The eyes' shape at the same stops: the squash both eyes share, the leading eye's own, the vertical
    /// squash, and the tilt.
    private static let shapes: [[Double]] = [
        [0, 0, 0, 0, 0], [0.15, 0, 0, 0, 0],
        [0.165, -0.0176, 0.008, -0.027, 0.648], [0.31, -0.0176, 0.008, -0.027, 0.648],
        [0.325, -0.022, -0.01, -0.003, 0.09], [0.47, -0.022, -0.01, -0.003, 0.09],
        [0.485, -0.0033, 0.0015, -0.0255, -0.115], [0.63, -0.0033, 0.0015, -0.0255, -0.115],
        [0.645, -0.0165, -0.0075, -0.024, -0.54], [0.79, -0.0165, -0.0075, -0.024, -0.54],
        [0.805, -0.022, 0.01, -0.0045, 0.135], [0.985, -0.022, 0.01, -0.0045, 0.135],
        [1, 0, 0, 0, 0],
    ]

    private static func cycle(_ time: Double, period: Double) -> Double {
        let turn = time / period
        return turn - turn.rounded(.down)
    }

    /// Every other pass runs backward. It is reversed before the easing curve, so both directions ease alike.
    private static func alternate(_ time: Double, period: Double) -> Double {
        let turn = time / period
        let pass = turn.rounded(.down)
        let part = turn - pass
        return pass.truncatingRemainder(dividingBy: 2) == 0 ? part : 1 - part
    }

    /// The value in `column` at `position`, linear between stops. Two equal stops hold a fixation still, and
    /// the short span after them is the flick to the next.
    private static func stop(_ position: Double, _ table: [[Double]], _ column: Int) -> Double {
        for index in table.indices.reversed() where position >= table[index][0] {
            guard index + 1 < table.count else { return table[index][column] }
            let span = table[index + 1][0] - table[index][0]
            guard span > 0 else { return table[index][column] }
            return table[index][column]
                + (table[index + 1][column] - table[index][column]) * ((position - table[index][0]) / span)
        }
        return table[0][column]
    }
}

/// CSS's timing functions, since every curve here is written in them.
nonisolated private enum Curve {
    static func easeIn(_ x: Double) -> Double { solve(x, 0.42, 0, 1, 1) }
    static func easeOut(_ x: Double) -> Double { solve(x, 0, 0, 0.58, 1) }
    static func easeInOut(_ x: Double) -> Double { solve(x, 0.42, 0, 0.58, 1) }
    static func morph(_ x: Double) -> Double { solve(x, 0.45, 0.05, 0.5, 1) }
    static func lift(_ x: Double) -> Double { solve(x, 0.23, 1, 0.32, 1) }

    /// Returns the curve's y at `x`. The curve's parameter for `x` is found by Newton's method, starting from `x`.
    private static func solve(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        var t = x
        for _ in 0..<8 {
            let error = ((ax * t + bx) * t + cx) * t - x
            if abs(error) < 1e-5 { break }
            let slope = (3 * ax * t + 2 * bx) * t + cx
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        return ((ay * t + by) * t + cy) * t
    }
}

/// The geometry of the peeled circle. `fold` is the circle's center reflected across the fold line, and the
/// flap is an arc of an equal circle centered there, which is what makes it a peel rather than a bite.
nonisolated private struct Peel {
    let center: CGPoint, fold: CGPoint, radius: CGFloat, rim: CGFloat
    /// Where the flap meets the circle, and where the cut does: the two differ by the curl.
    let met: [CGPoint], cut: [CGPoint]

    init(in rect: CGRect) {
        let side = min(rect.width, rect.height)
        let reach = Face.radius * side
        let curl = Face.rim * reach
        let middle = CGPoint(x: rect.midX, y: rect.midY)
        let away = 2 * Face.fold * reach
        let along = CGPoint(x: cos(-.pi / 4), y: sin(-.pi / 4))

        func pair(_ distance: CGFloat) -> [CGPoint] {
            let off = sqrt(max(0, reach * reach - distance * distance))
            return [1.0, -1.0].map {
                CGPoint(x: middle.x + distance * along.x - $0 * off * along.y,
                        y: middle.y + distance * along.y + $0 * off * along.x)
            }
        }

        center = middle
        radius = reach
        rim = curl
        fold = CGPoint(x: middle.x + away * along.x, y: middle.y + away * along.y)
        met = pair(away / 2)
        cut = pair((away * away + reach * reach - curl * curl) / (2 * away))
    }

    func angle(from point: CGPoint, to target: CGPoint) -> Angle {
        .radians(atan2(target.y - point.y, target.x - point.x))
    }
}

/// The circle with the corner peeled off it, as in `Logo/Logo.xcassets/PeelGlyph.imageset`.
nonisolated private struct PeelBody: Shape {
    func path(in rect: CGRect) -> Path {
        let peel = Peel(in: rect)
        var path = Path()
        path.addArc(center: peel.center, radius: peel.radius,
                    startAngle: peel.angle(from: peel.center, to: peel.cut[0]),
                    endAngle: peel.angle(from: peel.center, to: peel.cut[1]), clockwise: false)
        path.addArc(center: peel.fold, radius: peel.rim,
                    startAngle: peel.angle(from: peel.fold, to: peel.cut[1]),
                    endAngle: peel.angle(from: peel.fold, to: peel.cut[0]), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The peeled corner itself, folded back over the circle.
nonisolated private struct PeelFlap: Shape {
    func path(in rect: CGRect) -> Path {
        let peel = Peel(in: rect)
        var path = Path()
        path.addArc(center: peel.fold, radius: peel.radius,
                    startAngle: peel.angle(from: peel.fold, to: peel.met[1]),
                    endAngle: peel.angle(from: peel.fold, to: peel.met[0]), clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// The face's measurements, in a square 100 units wide with y running down, like an SVG `viewBox`. `radius`
/// is a fraction of that side. The shape is the logo's in `Logo/`, drawn here so it can move, and a change to the
/// logo's shape changes these too.
nonisolated private enum Face {
    static let radius = 0.4853
    /// How far the fold sits from the middle, in radii. Higher peels less; 0.606 is the logo's own.
    static let fold = 0.8
    /// The radius of the cut edge's arc (its curl), in radii of the circle.
    static let rim = 1.1212
    /// The point the eyes rest around: the center of the largest circle that fits in the orange left at this
    /// `fold`, which is 84% of the circle.
    static let center = (x: 41.0, y: 59.0)
    static let gap = 10.5
    static let eye = CGSize(width: 10, height: 22)
    /// How far the head moves with the look, in units, and how far it leans, in degrees.
    static let turn = (x: 8.4, y: 7.0)
    static let lean = 8.0
    /// How far looking down takes the eyes, which every other look matches: see `reach(toward:)`.
    static let down = 10.0
    /// How close the right eye's middle comes to the cut: the 10.5 units the eye reaches toward it, smiling or
    /// not, and 4 to spare.
    static let peelClearance = 14.5
    /// The time constant of the look's pursuit, in milliseconds. blobatar uses 110 for a face that fills a page,
    /// but at sidebar size that reads as lag, and what matters here is where the eyes point, not the glide.
    static let settle = 60.0
    /// Where `Surprise`'s dot sits, beyond the top right of the circle where the look goes, and its radius.
    static let dot = (x: 96.0, y: 4.0, radius: 6.0)

    /// How far the eyes go toward `aim`: as far from the circle's middle as looking down takes them, or to
    /// `peelClearance` from the cut, whichever comes first. The eyes rest below and left of that middle, so one
    /// distance in every direction would overdo looks down and left and barely show looks up and right.
    static func reach(toward aim: CGSize) -> Double {
        let length = hypot(aim.width, aim.height)
        guard length > 0 else { return 0 }
        let way = CGSize(width: aim.width / length, height: aim.height / length)
        let peel = Peel(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        let rest = CGPoint(x: center.x, y: center.y)
        let lookingDown = hypot(rest.x - peel.center.x, rest.y + down - peel.center.y)
        let even = crossings(from: rest, along: way, circle: peel.center, radius: lookingDown)?.far ?? down
        let rightEye = CGPoint(x: rest.x + gap, y: rest.y)
        let cut = crossings(from: rightEye, along: way, circle: peel.fold, radius: peel.rim + peelClearance)?.near ?? -1
        return cut > 0 ? min(even, cut) : even
    }

    /// How far along `way` from `point` the line enters the circle and leaves it, if it meets it at all.
    private static func crossings(from point: CGPoint, along way: CGSize, circle: CGPoint,
                                  radius: Double) -> (near: Double, far: Double)? {
        let offset = CGSize(width: point.x - circle.x, height: point.y - circle.y)
        let along = offset.width * way.width + offset.height * way.height
        let square = along * along - (offset.width * offset.width + offset.height * offset.height - radius * radius)
        guard square >= 0 else { return nil }
        return (-along - square.squareRoot(), -along + square.squareRoot())
    }
}

/// A superellipse, |x/a|^n + |y/b|^n = 1, drawn with four cubic Bezier curves: an ellipse at n = 2, and
/// squarer as n grows.
nonisolated private struct Superellipse: Shape {
    var n: Double

    func path(in rect: CGRect) -> Path {
        let k = min(1, (8 * pow(2, -1 / n) - 4) / 3)
        let a = rect.width / 2, b = rect.height / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * a, y: center.y + y * b)
        }

        var path = Path()
        path.move(to: point(1, 0))
        path.addCurve(to: point(0, 1), control1: point(1, k), control2: point(k, 1))
        path.addCurve(to: point(-1, 0), control1: point(-k, 1), control2: point(-1, k))
        path.addCurve(to: point(0, -1), control1: point(-1, -k), control2: point(-k, -1))
        path.addCurve(to: point(1, 0), control1: point(k, -1), control2: point(1, -k))
        path.closeSubpath()
        return path
    }
}
