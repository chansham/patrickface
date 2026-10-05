import SwiftUI
import Combine
import CryptoKit
import ImageIO

/// The separate organic arms indicate the actual time; they are not a pet animation.
struct PatrickClockManifest: Decodable {
    struct Body: Decodable { let regionIndex: Int; let anchorPixels: [Double]; let stageAnchor: [Double]; let pixelScale: Double }
    struct Hand: Decodable { let id: String; let regionIndex: Int; let pivotPixels: [Double]; let lengthPixels: Double; let displayLength: Double; let sourceDirectionDegrees: Double }
    struct Layout: Decodable { let coordinateSize: [Double]; let pivot: [Double] }
    let schemaVersion: Int
    let source: PatrickFrameRegions.Source
    let frameRegions: PatrickFrameRegionsReference
    let canvas: PatrickFrameRegions.Canvas
    let body: Body
    let hands: [Hand]
    let layout: Layout
}

@MainActor final class PatrickClockArtwork: ObservableObject {
    @Published private(set) var manifest: PatrickClockManifest?
    @Published private(set) var images: [CGImage] = []
    @Published private(set) var message = "手臂時計素材尚未載入"
    private var attempted = false

    func load(bundle: Bundle = .main) {
        guard !attempted else { return }; attempted = true
        do {
            guard let url = PatrickExperienceResources.url("experience/clock/manifest.json", bundle: bundle) else { throw ArtworkError.invalid }
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(PatrickClockManifest.self, from: data)
            guard value.schemaVersion == 1,
                  let atlasURL = PatrickExperienceResources.url(value.source.path, bundle: bundle),
                  let regionsURL = PatrickExperienceResources.url(value.frameRegions.path, bundle: bundle) else { throw ArtworkError.invalid }
            let atlasData = try Data(contentsOf: atlasURL), regionsData = try Data(contentsOf: regionsURL)
            guard Self.sha(atlasData) == value.source.sha256.lowercased(),
                  Self.sha(regionsData) == value.frameRegions.sha256.lowercased(),
                  let source = CGImageSourceCreateWithData(atlasData as CFData, nil),
                  let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  atlas.width == value.source.width, atlas.height == value.source.height else { throw ArtworkError.invalid }
            let regions = try JSONDecoder().decode(PatrickFrameRegions.self, from: regionsData)
            let clipObject: [String: Any] = ["id": "clock-layers", "title": "原味手臂時計",
                "atlas": value.source.path, "width": value.source.width, "height": value.source.height,
                "frameCount": regions.frames.count, "durationsMs": Array(repeating: 100, count: regions.frames.count),
                "sha256": value.source.sha256, "anchorNormalized": value.canvas.anchorNormalized,
                "frameRegions": ["path": value.frameRegions.path, "sha256": value.frameRegions.sha256, "version": value.frameRegions.version]]
            let clip = try JSONDecoder().decode(PatrickAnimationClip.self, from: JSONSerialization.data(withJSONObject: clipObject))
            guard regions.unavailableReason(for: clip) == nil,
                  regions.canvas.width == value.canvas.width, regions.canvas.height == value.canvas.height,
                  regions.canvas.anchorPixels == value.canvas.anchorPixels,
                  value.layout.coordinateSize.count == 2, value.layout.coordinateSize.allSatisfy({ $0.isFinite && $0 > 0 }),
                  Self.point(value.layout.pivot), Self.point(value.body.anchorPixels), Self.point(value.body.stageAnchor),
                  value.body.pixelScale.isFinite, (0.01...4).contains(value.body.pixelScale),
                  regions.frames.indices.contains(value.body.regionIndex),
                  Set(value.hands.map(\.id)) == Set(["hour", "minute"]), value.hands.count == 2,
                  value.hands.allSatisfy({ regions.frames.indices.contains($0.regionIndex) && Self.point($0.pivotPixels)
                    && $0.lengthPixels.isFinite && $0.lengthPixels > 0 && $0.displayLength.isFinite && $0.displayLength > 0
                    && $0.displayLength <= value.layout.coordinateSize.max()! && $0.sourceDirectionDegrees.isFinite }) else { throw ArtworkError.invalid }
            images = try regions.frames.map { try PatrickAnimationPlayer.renderRegion(atlas: atlas, frame: $0, canvas: regions.canvas) }
            manifest = value; message = "原味手臂時計"
        } catch { images = []; manifest = nil; message = "手臂時計資料未能載入，仍可使用數字時間" }
    }
    private static func point(_ values: [Double]) -> Bool { values.count == 2 && values.allSatisfy({ $0.isFinite && abs($0) <= 16384 }) }
    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private enum ArtworkError: Error { case invalid }
}

@MainActor struct PatrickOrganicClock: View {
    @ObservedObject var artwork: PatrickClockArtwork
    let dimmed: Bool
    var body: some View {
        TimelineView(.everyMinute) { tick in
            Canvas { context, size in
                guard let m = artwork.manifest else { return }
                let unit = min(size.width / m.layout.coordinateSize[0], size.height / m.layout.coordinateSize[1])
                context.translateBy(x: (size.width - m.layout.coordinateSize[0] * unit) / 2,
                                    y: (size.height - m.layout.coordinateSize[1] * unit) / 2)
                context.scaleBy(x: unit, y: unit)
                context.opacity = dimmed ? 0.55 : 1
                let b = m.body, s = b.pixelScale
                context.draw(Image(decorative: artwork.images[b.regionIndex], scale: 1), in: CGRect(
                    x: b.stageAnchor[0] - b.anchorPixels[0] * s, y: b.stageAnchor[1] - b.anchorPixels[1] * s,
                    width: Double(m.canvas.width) * s, height: Double(m.canvas.height) * s))
                let parts = Calendar.current.dateComponents([.hour, .minute], from: tick.date)
                let minute = Double(parts.minute ?? 0), hour = Double((parts.hour ?? 0) % 12)
                for hand in m.hands {
                    var layer = context
                    layer.translateBy(x: m.layout.pivot[0], y: m.layout.pivot[1])
                    let angle = hand.id == "hour" ? hour * 30 + minute * 0.5 : minute * 6
                    layer.rotate(by: .degrees(angle - 90 - hand.sourceDirectionDegrees))
                    let scale = hand.displayLength / hand.lengthPixels
                    layer.scaleBy(x: scale, y: scale)
                    layer.draw(Image(decorative: artwork.images[hand.regionIndex], scale: 1), in: CGRect(
                        x: -hand.pivotPixels[0], y: -hand.pivotPixels[1], width: Double(m.canvas.width), height: Double(m.canvas.height)))
                }
            }
        }.accessibilityHidden(true)
    }
}

/// Decoration has its own fixed positions and never moves a character layer.
struct PatrickSceneAmbience: View {
    let scene: String
    var motionAllowed = false
    private var bubbles: Bool { scene == "charging" || scene == "bath" }
    var body: some View {
        Group {
            if bubbles && motionAllowed {
                TimelineView(.animation(minimumInterval: 0.125)) { tick in
                    decorations(phase: tick.date.timeIntervalSinceReferenceDate)
                }
            } else { decorations(phase: nil) }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    private func decorations(phase: TimeInterval?) -> some View {
        GeometryReader { geometry in
            ForEach(0..<5, id: \.self) { index in
                let progress = phase.map { (($0 / (7 + Double(index)) + Double(index) * 0.19).truncatingRemainder(dividingBy: 1)) }
                Image(systemName: scene == "sleeping" ? "star.fill" : scene == "celebrate" ? "sparkle" : "circle")
                    .font(.system(size: CGFloat(6 + index % 3 * 3)))
                    .foregroundStyle(Color.white.opacity(progress.map { 0.24 * sin($0 * .pi) } ?? 0.18))
                    .position(x: geometry.size.width * ((index.isMultiple(of: 2) ? 0.12 : 0.88) + (progress.map { sin($0 * 2 * .pi) * 0.035 } ?? 0)),
                              y: geometry.size.height * (progress.map { 0.92 - $0 * 0.65 } ?? (0.28 + Double(index) * 0.12)))
            }
        }
    }
}
