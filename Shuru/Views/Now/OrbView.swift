import SwiftUI
import UIKit

/// The soft, slowly moving orb behind the next task.
///
/// Core Animation moves it, not SwiftUI: the system works out every frame at the screen's own refresh rate,
/// so the motion stays even no matter what the app is busy with.
struct OrbView: UIViewRepresentable {
    let colors: OrbColors
    let dark: Bool
    let blur: CGFloat
    /// 1 is normal pace; 0 holds it still (hidden page, Reduce Motion).
    let speed: Double

    func makeUIView(context: Context) -> OrbUIView { OrbUIView() }

    func updateUIView(_ view: OrbUIView, context: Context) {
        view.configure(colors: colors, dark: dark, blur: blur, speed: speed)
    }
}

final class OrbUIView: UIView {
    private struct Blob {
        let size: CGFloat
        let offset: CGPoint
        /// Seconds per orbit; negative goes the other way.
        let period: Double
        /// Seconds per stretch-and-squash.
        let morph: Double
        let blurAdjust: CGFloat
    }

    private static let blobs = [
        Blob(size: 230, offset: CGPoint(x: -41, y: -37), period: 22, morph: 11, blurAdjust: 0),
        Blob(size: 210, offset: CGPoint(x: 47, y: 27), period: -28, morph: 13, blurAdjust: 0),
        Blob(size: 180, offset: CGPoint(x: -20, y: 60), period: 17, morph: 9, blurAdjust: -2),
    ]

    /// Its speed is the orb's pace. Changing it re-times smoothly, so the orb never jumps.
    private let clock = CALayer()
    private let breathe = CALayer()
    private let glow = CAGradientLayer()
    private var orbits: [CALayer] = []
    private var spins: [CALayer] = []
    private var morphs: [CALayer] = []
    private var gradients: [CAGradientLayer] = []

    private var lastColors: [UIColor] = []
    private var lastBlur: CGFloat = -1
    private var lastDark: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = false

        layer.addSublayer(clock)
        clock.addSublayer(breathe)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: 520, height: 520)
        breathe.addSublayer(glow)

        for b in Self.blobs {
            let orbit = CALayer(), arm = CALayer(), spin = CALayer(), morph = CALayer()
            let gradient = CAGradientLayer()
            gradient.type = .radial
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            arm.position = b.offset
            breathe.addSublayer(orbit)
            orbit.addSublayer(arm)
            arm.addSublayer(spin)
            spin.addSublayer(morph)
            morph.addSublayer(gradient)
            orbits.append(orbit)
            spins.append(spin)
            morphs.append(morph)
            gradients.append(gradient)
        }

        let still: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "colors": NSNull(),
                                         "locations": NSNull(), "opacity": NSNull(), "transform": NSNull()]
        let all: [CALayer] = [clock, breathe, glow] + orbits + spins + morphs + gradients.map { $0 as CALayer }
        for l in all { l.actions = still }

        addAnimations()
        NotificationCenter.default.addObserver(self, selector: #selector(restoreAnimations),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clock.frame = bounds
        breathe.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restoreAnimations()
    }

    func configure(colors: OrbColors, dark: Bool, blur: CGFloat, speed: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let palette = [colors.c1, colors.c2, colors.c3, colors.glow].map { UIColor($0) }
        if palette != lastColors || blur != lastBlur || dark != lastDark {
            lastColors = palette
            lastBlur = blur
            lastDark = dark
            glow.colors = [palette[3].cgColor, palette[3].withAlphaComponent(0).cgColor]
            for (i, b) in Self.blobs.enumerated() {
                let sigma = max(0.5, Double(blur + b.blurAdjust))
                let r = Double(b.size) / 2
                let outer = r + 3 * sigma
                let g = gradients[i]
                g.bounds = CGRect(x: 0, y: 0, width: 2 * outer, height: 2 * outer)
                let stops = Self.falloff(radius: r, sigma: sigma)
                g.colors = stops.map { palette[i].withAlphaComponent(palette[i].cgColor.alpha * $0.alpha).cgColor }
                g.locations = stops.map { NSNumber(value: $0.location) }
                g.opacity = dark ? 0.72 : 0.85
            }
        }
        let pace = Float(max(0, speed))
        if clock.speed != pace { retime(to: pace) }
        CATransaction.commit()
    }

    // MARK: Time

    /// Changes the pace without a jump: the orb carries on from exactly where it is.
    private func retime(to pace: Float) {
        let now = CACurrentMediaTime()
        let local = clock.convertTime(now, from: nil)
        let parent = layer.convertTime(now, from: nil)
        clock.speed = pace
        clock.timeOffset = local
        clock.beginTime = parent
    }

    @objc private func restoreAnimations() {
        guard orbits.first?.animation(forKey: "orbit") == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addAnimations()
        CATransaction.commit()
    }

    private func addAnimations() {
        for (i, b) in Self.blobs.enumerated() {
            let turn = b.period < 0 ? -1.0 : 1.0
            let period = abs(b.period)
            // Around the centre, once per period…
            orbits[i].add(Self.rotation(by: 2 * .pi * turn, over: period), forKey: "orbit")
            // …while the blob itself turns half as fast (net), like before.
            spins[i].add(Self.rotation(by: -.pi * turn, over: period), forKey: "spin")
            // Gentle stretch and squash.
            morphs[i].add(Self.wave(over: b.morph) { s in
                NSValue(caTransform3D: CATransform3DMakeScale(1 + 0.06 * s, 1 - 0.06 * s, 1))
            }, forKey: "morph")
        }
        breathe.add(Self.wave(over: 7) { s in
            NSValue(caTransform3D: CATransform3DMakeScale(0.995 + 0.045 * s, 0.995 + 0.045 * s, 1))
        }, forKey: "breathe")
    }

    private static func rotation(by angle: Double, over duration: Double) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = angle
        a.duration = duration
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .linear)
        a.isRemovedOnCompletion = false
        // A random start, so it doesn't look the same every launch.
        a.timeOffset = Double.random(in: 0..<duration)
        return a
    }

    /// One period of a sine, sampled finely enough to look smooth, repeating forever.
    private static func wave(over duration: Double, value: (Double) -> NSValue) -> CAKeyframeAnimation {
        let n = 72
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = (0...n).map { k in value(sin(2 * .pi * Double(k) / Double(n))) }
        a.keyTimes = (0...n).map { NSNumber(value: Double($0) / Double(n)) }
        a.calculationMode = .linear
        a.duration = duration
        a.repeatCount = .infinity
        a.isRemovedOnCompletion = false
        a.timeOffset = Double.random(in: 0..<duration)
        return a
    }

    /// A soft edge with the falloff of a Gaussian blur (½·erfc), as gradient stops.
    private static func falloff(radius r: Double, sigma: Double) -> [(location: Double, alpha: CGFloat)] {
        let profile: [(d: Double, a: CGFloat)] = [
            (-2.5, 0.994), (-2, 0.977), (-1.5, 0.933), (-1, 0.841), (-0.5, 0.691), (0, 0.5),
            (0.5, 0.309), (1, 0.159), (1.5, 0.067), (2, 0.023), (2.5, 0.006), (3, 0),
        ]
        let outer = r + 3 * sigma
        var stops: [(location: Double, alpha: CGFloat)] = [(0, 1)]
        for p in profile {
            let loc = (r + p.d * sigma) / outer
            guard loc > 0 else { continue }
            stops.append((min(1, loc), p.a))
        }
        return stops
    }
}
