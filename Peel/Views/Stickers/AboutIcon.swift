import AppKit
import PeelCore
import SwiftUI

/// About's icon, which answers clicks: each one squashes it a little, and the fifth in a row wakes Peel's face on its
/// sticker for `WakeUp`'s scene, the sticker moving on its own while the box stays. Drawn by Core Animation, as the
/// sidebar's face is, so a frame moves layers and lays nothing out.
struct AboutIcon: NSViewRepresentable {
    /// A click the icon answers: when it came, on the clock the display link keeps, and what it does.
    struct Reaction: Equatable {
        let start: CFTimeInterval
        let answer: Pokes.Answer
        let reducingMotion: Bool
    }

    /// Changes whenever macOS draws the icon otherwise: another appearance or icon style.
    let style: Int
    let colorScheme: ColorScheme
    let reaction: Reaction?
    let finished: () -> Void

    func makeNSView(context: Context) -> AboutIconView {
        AboutIconView()
    }

    func updateNSView(_ view: AboutIconView, context: Context) {
        view.finished = finished
        view.style = (style, colorScheme)
        view.answer(reaction)
    }
}

final class AboutIconView: NSView {
    static let side: CGFloat = 96
    var finished: () -> Void = {}
    var style: (Int, ColorScheme)? {
        didSet {
            guard let style, oldValue.map({ $0.0 != style.0 || $0.1 != style.1 }) ?? true else { return }
            redraw()
        }
    }

    /// Flipped so that y runs down from the top left, as `Face` writes every position.
    private let canvas = CALayer()
    private let box = CALayer()
    private let sticker = CALayer()
    private let face = CALayer()
    private let cheeks = [CAGradientLayer(), CAGradientLayer()]
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    private let lids = [CAShapeLayer(), CAShapeLayer()]
    private var link: CADisplayLink?
    private var reaction: AboutIcon.Reaction?
    private var squash = Squash()
    private var icon: CGImage?
    /// The box and the sticker apart, once worked out for the icon shown, and only when the sticker comes away whole.
    private var parts: (box: CGImage, sticker: CGImage)?
    private var cutting: Task<Void, Never>?
    /// Whether the scene under way moves the sticker, decided as it starts from the parts ready then.
    private var movesSticker = false

    private static let middle = CGPoint(x: IconCut.center.x * side, y: IconCut.center.y * side)
    private static let radius = IconCut.radius * side
    /// Points to one of the face's units on the sticker.
    private static let unit = radius / (Face.radius * 100)

    init() {
        let square = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        super.init(frame: square)
        wantsLayer = true
        canvas.isGeometryFlipped = true
        canvas.frame = square
        for layer in [box, sticker] {
            layer.bounds = square
            layer.contentsGravity = .resize
            // The parts are drawn at twice the screen's pixels, so a turned or squashed sticker keeps its edges.
            layer.minificationFilter = .trilinear
        }
        box.position = CGPoint(x: Self.side / 2, y: Self.side / 2)
        sticker.anchorPoint = CGPoint(x: Self.middle.x / Self.side, y: Self.middle.y / Self.side)
        sticker.position = Self.middle
        face.frame = square
        face.opacity = 0
        let eye = CGRect(x: 0, y: 0, width: Face.eye.width * Self.unit, height: Face.eye.height * Self.unit)
        for layer in eyes {
            layer.bounds = eye
            layer.path = Superellipse(n: 3).path(in: eye).cgPath
        }
        for layer in lids {
            layer.frame = square
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineWidth = eye.width * 0.42
            layer.opacity = 0
        }
        for layer in cheeks {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            layer.bounds = CGRect(x: 0, y: 0, width: 14 * Self.unit, height: 14 * Self.unit * 0.55)
            layer.opacity = 0
        }
        face.sublayers = cheeks + eyes + lids
        sticker.addSublayer(face)
        box.addSublayer(sticker)
        canvas.addSublayer(box)
        layer?.addSublayer(canvas)
        recolor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    /// Takes no clicks, so they reach the gesture About puts on the icon.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window == nil else { return redraw() }
        link?.invalidate()
        link = nil
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recolor()
        redraw()
    }

    /// Starts what a click asks for, or comes back to rest once nothing is left to answer.
    func answer(_ reaction: AboutIcon.Reaction?) {
        guard reaction != self.reaction else { return }
        self.reaction = reaction
        guard let reaction else { return rest() }
        if !reaction.reducingMotion {
            let count = if case .squash(let count) = reaction.answer { count } else { Pokes.toWake }
            squash.press(at: reaction.start, count: count)
        }
        if reaction.answer == .wake, !reaction.reducingMotion, let parts {
            movesSticker = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            box.contents = parts.box
            sticker.contents = parts.sticker
            CATransaction.commit()
        }
        if link == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        link?.isPaused = false
        draw(at: CACurrentMediaTime())
    }

    @objc private func tick(_ link: CADisplayLink) {
        draw(at: link.targetTimestamp)
    }

    private func draw(at time: CFTimeInterval) {
        guard let reaction else { return }
        let elapsed = time - reaction.start
        let scene = reaction.answer == .wake ? WakeUp(elapsed: elapsed, reducingMotion: reaction.reducingMotion) : nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.transform = Self.squashing(by: squash.amount(at: time), leaning: squash.tilt(at: time),
                                       footBelowAnchor: Self.side / 2)
        if let scene { pose(scene) }
        CATransaction.commit()
        if squash.isOver(at: time), scene?.isOver ?? true {
            rest()
            finished()
        }
    }

    private func pose(_ scene: WakeUp) {
        if movesSticker {
            sticker.transform = CATransform3DConcat(
                Self.squashing(by: scene.squash, leaning: scene.tilt, growing: scene.breath,
                               footBelowAnchor: Self.radius),
                CATransform3DMakeTranslation(scene.shift, -scene.hop, 0)
            )
        }
        face.opacity = Float(scene.presence)
        for (index, side) in [-1.0, 1.0].enumerated() {
            let eye = side < 0 ? scene.left : scene.right
            let center = Self.point(Face.center.x + side * Face.gap + scene.look, Face.center.y - eye.lift)
            let arch = min(1, eye.bend / 0.35)
            eyes[index].position = center
            eyes[index].transform = CATransform3DMakeScale(
                (1 - 0.07 * abs(scene.look) / 9) * (1 + scene.widen),
                scene.openness * (1 - 0.92 * eye.closed) * (1 + scene.widen),
                1
            )
            eyes[index].opacity = Float(1 - arch)
            lids[index].opacity = Float(arch)
            if arch > 0 { lids[index].path = Self.lid(at: center, bending: eye.bend) }
            cheeks[index].position = Self.point(Face.center.x + side * 14 + scene.look / 2, 72)
            cheeks[index].opacity = Float(scene.blush / 0.6)
        }
    }

    /// The icon at rest: the whole icon on the box, nothing moved, and no face.
    private func rest() {
        link?.isPaused = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.transform = CATransform3DIdentity
        sticker.transform = CATransform3DIdentity
        box.contents = icon
        sticker.contents = nil
        face.opacity = 0
        CATransaction.commit()
        movesSticker = false
        squash = Squash()
    }

    /// Draws the icon as macOS draws it in this appearance, at twice the screen's pixels, and works out its parts
    /// off the main thread. A scene under way keeps the parts it started with.
    private func redraw() {
        guard let window else { return }
        let scale = window.backingScaleFactor * 2
        let pixels = Int(Self.side * scale)
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
        }
        guard let icon = context.makeImage(), let data = context.data else { return }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                              count: pixels * pixels * 4))
        self.icon = icon
        for layer in [canvas, box, sticker, face] + cheeks + eyes + lids {
            layer.contentsScale = scale
        }
        if reaction == nil { box.contents = icon }
        cutting?.cancel()
        cutting = Task { [weak self] in
            let cut = await Task.detached(priority: .utility) { IconCut(pixels: bytes, side: pixels) }.value
            guard !Task.isCancelled, let self else { return }
            parts = cut.isWhole ? Self.images(cut, side: pixels, space: space) : nil
        }
    }

    private static func images(_ cut: IconCut, side: Int, space: CGColorSpace) -> (box: CGImage, sticker: CGImage)? {
        func image(_ bytes: [UInt8]) -> CGImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                           space: space, bitmapInfo: alpha, provider: provider, decode: nil, shouldInterpolate: true,
                           intent: .defaultIntent)
        }
        guard let box = image(cut.box), let sticker = image(cut.sticker) else { return nil }
        return (box, sticker)
    }

    /// Resolves the face's colors for the view's appearance. The eyes' `faceInk` is one color in every appearance,
    /// because they always sit on orange.
    private func recolor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = NSColor(resource: .faceInk).cgColor
            for layer in eyes { layer.fillColor = ink }
            for layer in lids { layer.strokeColor = ink }
            let red = NSColor(resource: .peelRedFill)
            for layer in cheeks {
                layer.colors = [red.withAlphaComponent(0.55).cgColor, red.withAlphaComponent(0).cgColor]
            }
        }
    }

    /// A lean about the layer's anchor, then a squash and stretch about the foot `footBelowAnchor` points below it.
    private static func squashing(by amount: Double, leaning tilt: Double, growing growth: Double = 0,
                                  footBelowAnchor foot: CGFloat) -> CATransform3D {
        let grow = 1 + growth
        let lean = CATransform3DMakeRotation(tilt * .pi / 180, 0, 0, 1)
        let squash = CATransform3DConcat(
            CATransform3DConcat(CATransform3DMakeTranslation(0, -foot, 0),
                                CATransform3DMakeScale(grow * (1 - 0.66 * amount), grow * (1 + amount), 1)),
            CATransform3DMakeTranslation(0, foot, 0)
        )
        return CATransform3DConcat(lean, squash)
    }

    /// Where a point of the face's 100 unit square falls on the icon.
    private static func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: middle.x + (x - 50) * unit, y: middle.y + (y - 50) * unit)
    }

    /// The closed eye: a line under where the eye was, bent up into an arch as far as `bend` says.
    private static func lid(at center: CGPoint, bending bend: Double) -> CGPath {
        let width = Face.eye.width * unit, height = Face.eye.height * unit
        let base = center.y + 0.12 * height
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - 0.7 * width, y: base))
        path.addQuadCurve(to: CGPoint(x: center.x + 0.7 * width, y: base),
                          control: CGPoint(x: center.x, y: base - bend * 0.42 * height))
        return path
    }
}
