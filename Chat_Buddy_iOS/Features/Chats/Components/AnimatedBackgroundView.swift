import SwiftUI
import SpriteKit

// MARK: - Animated Background Type

enum AnimatedBackground: String, CaseIterable, Codable {
    case none
    case aurora    // Slow-drifting colored orbs (Canvas, no SpriteKit)
    case stars     // Drifting starfield
    case snow      // Falling snowflakes
    case rain      // Diagonal rain streaks
    case fire      // Rising ember particles

    var displayName: String {
        switch self {
        case .none:   return "Static"
        case .aurora: return "Aurora Particles"
        case .stars:  return "Starfield"
        case .snow:   return "Snowfall"
        case .rain:   return "Rain"
        case .fire:   return "Ember Glow"
        }
    }

    var localizationKey: String {
        switch self {
        case .none:   return "none"
        case .aurora: return "bg_animated_aurora"
        case .stars:  return "bg_animated_stars"
        case .snow:   return "bg_animated_snow"
        case .rain:   return "bg_animated_rain"
        case .fire:   return "bg_animated_fire"
        }
    }
}

// MARK: - Animated Background View

/// Composites a static gradient preset with an optional particle animation layer.
/// Uses SwiftUI Canvas for lightweight effects; falls back to SpriteKit for complex particles.
struct AnimatedBackgroundView: View {
    let preset: ChatBackgroundPreset
    let animation: AnimatedBackground

    var body: some View {
        ZStack {
            // 1. Static gradient base layer
            if let gradient = preset.gradient(opacity: 0.6) {
                Rectangle().fill(gradient).ignoresSafeArea()
            } else {
                Rectangle().fill(Color(UIColor.systemBackground)).ignoresSafeArea()
            }

            // 2. Particle animation layer
            switch animation {
            case .none:   EmptyView()
            case .aurora: AuroraView().ignoresSafeArea()
            case .stars:  ParticleKitView(emitterName: "Stars").ignoresSafeArea()
            case .snow:   ParticleKitView(emitterName: "Snow").ignoresSafeArea()
            case .rain:   ParticleKitView(emitterName: "Rain").ignoresSafeArea()
            case .fire:   ParticleKitView(emitterName: "Fire").ignoresSafeArea()
            }
        }
    }
}

// MARK: - Aurora (SwiftUI Canvas — zero SpriteKit overhead)

/// Animated floating orbs using SwiftUI TimelineView + Canvas.
/// Very low CPU cost; runs at display refresh rate via TimelineView.
struct AuroraView: View {
    private struct Orb {
        let baseX: Double; let baseY: Double
        let radius: Double; let color: Color
        let speedX: Double; let speedY: Double; let phase: Double
    }

    private static let orbs: [Orb] = [
        Orb(baseX: 0.2, baseY: 0.3, radius: 200, color: Color(hex: "#5E2BFF").opacity(0.25), speedX: 0.04, speedY: 0.03, phase: 0),
        Orb(baseX: 0.7, baseY: 0.2, radius: 240, color: Color(hex: "#00CFFF").opacity(0.20), speedX: 0.03, speedY: 0.05, phase: 1.1),
        Orb(baseX: 0.5, baseY: 0.7, radius: 180, color: Color(hex: "#FF2290").opacity(0.18), speedX: 0.05, speedY: 0.04, phase: 2.3),
        Orb(baseX: 0.85, baseY: 0.6, radius: 160, color: Color(hex: "#00FFA3").opacity(0.15), speedX: 0.06, speedY: 0.03, phase: 0.7),
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for orb in Self.orbs {
                    let x = orb.baseX * size.width  + sin(t * orb.speedX + orb.phase) * 60
                    let y = orb.baseY * size.height + cos(t * orb.speedY + orb.phase) * 60
                    let rect = CGRect(x: x - orb.radius, y: y - orb.radius,
                                     width: orb.radius * 2, height: orb.radius * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(orb.color))
                }
            }
            .blur(radius: 60)
            .blendMode(.screen)
        }
    }
}

// MARK: - Generic SpriteKit Particle View

/// Wraps a `.sks` particle emitter file inside a SwiftUI view.
/// The emitter is rendered in a SpriteKit scene for maximum performance.
struct ParticleKitView: UIViewRepresentable {
    let emitterName: String

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        let scene = ParticleScene(emitterName: emitterName)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}

private final class ParticleScene: SKScene {
    private let emitterName: String

    init(emitterName: String) {
        self.emitterName = emitterName
        // SKScene requires init(size:) — use a placeholder; size is set via scaleMode
        super.init(size: CGSize(width: 390, height: 844))
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        // Load .sks emitter; fall back to a programmatic emitter if file not found
        if let emitter = SKEmitterNode(fileNamed: "\(emitterName).sks") {
            emitter.position = CGPoint(x: frame.midX, y: frame.maxY)
            emitter.zPosition = 1
            addChild(emitter)
        } else {
            addChild(fallbackEmitter(for: emitterName))
        }
    }

    /// Programmatic fallback emitter — used if .sks files are not present in the bundle.
    private func fallbackEmitter(for name: String) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.position = CGPoint(x: frame.midX, y: frame.maxY)
        e.zPosition = 1

        switch name {
        case "Snow":
            e.particleBirthRate   = 40
            e.particleLifetime    = 6
            e.particleSpeed       = 80
            e.particleSpeedRange  = 40
            e.emissionAngle       = -.pi / 2 + 0.1
            e.emissionAngleRange  = 0.3
            e.particleAlpha       = 0.7
            e.particleAlphaRange  = 0.3
            e.particleScale       = 0.06
            e.particleScaleRange  = 0.04
            e.particleColor       = UIColor.white
            e.particleColorBlendFactor = 1
            e.particleTexture     = SKTexture(imageNamed: "spark")
        case "Rain":
            e.particleBirthRate   = 200
            e.particleLifetime    = 1.5
            e.particleSpeed       = 700
            e.emissionAngle       = -.pi / 2 - 0.2
            e.emissionAngleRange  = 0.05
            e.particleAlpha       = 0.35
            e.particleScale       = 0.02
            e.particleScaleRange  = 0.01
            e.particleColor       = UIColor(white: 0.8, alpha: 1)
            e.particleColorBlendFactor = 1
        case "Fire":
            e.position            = CGPoint(x: frame.midX, y: frame.minY)
            e.particleBirthRate   = 80
            e.particleLifetime    = 3
            e.particleSpeed       = 150
            e.particleSpeedRange  = 80
            e.emissionAngle       = .pi / 2
            e.emissionAngleRange  = .pi / 4
            e.particleAlpha       = 0.6
            e.particleAlphaRange  = 0.4
            e.particleScale       = 0.15
            e.particleScaleRange  = 0.1
            e.particleColorSequence = SKKeyframeSequence(
                keyframeValues: [UIColor.orange, UIColor.red, UIColor(white: 0.2, alpha: 0)],
                times: [0, 0.5, 1]
            )
            e.particleColorBlendFactor = 1
        default: // Stars
            e.particleBirthRate   = 2
            e.particleLifetime    = 20
            e.particleSpeed       = 12
            e.emissionAngle       = -.pi / 2
            e.emissionAngleRange  = .pi * 2
            e.particleAlpha       = 0.6
            e.particleAlphaRange  = 0.4
            e.particleScale       = 0.04
            e.particleScaleRange  = 0.03
            e.particleColor       = UIColor.white
            e.particleColorBlendFactor = 1
        }
        return e
    }
}
