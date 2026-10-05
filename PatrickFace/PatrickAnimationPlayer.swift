import SwiftUI
import CoreGraphics
import ImageIO
import CryptoKit

// Apple API references checked 2026-09-27:
// https://developer.apple.com/documentation/imageio/cgimagesource
// https://developer.apple.com/documentation/coregraphics/cgimage/cropping(to:)
// https://developer.apple.com/documentation/cryptokit/hashfunction
// https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_overview/dq_overview.html
/// A frame replaces another frame in a fixed viewport. No pose transform is used.
@MainActor
final class PatrickAnimationPlayer: ObservableObject {
    @Published private(set) var clips: [PatrickAnimationClip] = []
    @Published private(set) var image: CGImage?
    @Published private(set) var currentClipID: String?
    @Published private(set) var frameIndex = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var message = "正在讀取動作畫稿"
    @Published private(set) var anchor: [Double] = [0.5, 0.5]
    @Published private(set) var masterAnchor: [Double] = [0.5, 0.5]
    @Published private(set) var drawingScale = 1.0
    @Published private(set) var cellAspectRatio = 1.0
    var onClipStarted: ((String) -> Void)?
    /// A selected costume supplies its own actions. Missing entries stay missing.
    var eventClips: [String: String]?
    var idleClips: [String]?
    private var policy: PatrickAnimationPolicy
    private var context = PatrickAnimationContext()
    private var playTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var generation = UUID()
    private var restingImage: CGImage?
    private var restingClipID: String?
    private var restingAnchor: [Double] = [0.5, 0.5]
    private var restingScale = 1.0
    private var restingAspectRatio = 1.0
    private var resourceRoot: URL?
    private var loaded = false
    private var failedClips: [String: String] = [:]
    private let defaults: UserDefaults
    private static let yawnKey = "patrick.animation.last-yawn.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let timestamp = defaults.double(forKey: Self.yawnKey)
        policy = PatrickAnimationPolicy(lastYawnAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil)
    }

    func load(bundle: Bundle = .main) {
        guard !loaded else { return }
        loaded = true
        guard let url = bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Animation") else {
            message = "動作素材尚未放入 App"; return
        }
        resourceRoot = url.deletingLastPathComponent()
        do {
            let catalog = try JSONDecoder().decode(PatrickAnimationCatalog.self, from: Data(contentsOf: url))
            guard Set(catalog.clips.map(\.id)).count == catalog.clips.count else {
                throw PlaybackError.invalid("動作清單有重複名稱")
            }
            clips = catalog.clips
            if let master = catalog.master?.anchorNormalized, master.count == 2,
               master.allSatisfy({ $0.isFinite && (0...1).contains($0) }) {
                masterAnchor = master
            }
            // The available yawn first drawing is a static holding pose until idle art exists.
            // It is never substituted for a requested missing action.
            let restingIDs = PatrickAnimationPolicy.idleIDs + ["yawn"]
            for id in restingIDs {
                guard let clip = clips.first(where: { $0.id == id }), unavailableReason(for: clip) == nil else { continue }
                do {
                    let prepared = try prepareClip(clip)
                    restingImage = try prepared.frame(at: 0); restingAnchor = prepared.anchor
                    restingScale = clip.scale; restingAspectRatio = prepared.aspectRatio; break
                } catch {
                    failedClips[id] = "畫稿或輪廓資料讀取失敗"
                }
            }
            showRestingPose()
            message = restingImage == nil ? "待機畫稿尚未準備" : "安靜陪著你"
        } catch {
            message = "動作清單無法讀取"
        }
    }

    func unavailableReason(for clip: PatrickAnimationClip) -> String? {
        if let reason = failedClips[clip.id] ?? clip.unavailableReason { return reason }
        guard let path = clip.bundledAtlasPath, let root = resourceRoot,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else { return "畫稿尚未放入 App" }
        if let regions = clip.frameRegions {
            guard let path = regions.bundledPath,
                  FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else { return "輪廓資料尚未放入 App" }
        }
        return nil
    }

    @discardableResult
    func selectRestingClip(_ id: String?) -> Bool {
        stop(); restingClipID = id
        guard let id, let clip = clips.first(where: { $0.id == id }), unavailableReason(for: clip) == nil else {
            restingImage = nil; showRestingPose(); message = "這套造型的畫稿尚未準備"; return false
        }
        do {
            let prepared = try prepareClip(clip)
            restingImage = try prepared.frame(at: 0); restingAnchor = prepared.anchor
            restingScale = clip.scale; restingAspectRatio = prepared.aspectRatio
            showRestingPose(); message = "安靜陪著你"; scheduleIdle(); return true
        } catch {
            failedClips[id] = "造型畫稿無法讀取"
            restingImage = nil; showRestingPose(); message = "造型畫稿無法讀取"; return false
        }
    }

    func update(_ next: PatrickAnimationContext, at date: Date = .now) {
        let changed = next != context
        context = next
        let event = policy.transition(to: next, at: date)
        guard next.allowsMotion else {
            stop()
            if next.reduceMotion { message = "減少動態：靜靜陪著你" }
            else if next.lowPower { message = "低耗電模式：動作暫停" }
            return
        }
        if let event { playEvent(event, at: date) }
        else if changed && !isPlaying { scheduleIdle() }
    }

    func playEvent(_ event: String, at date: Date = .now) {
        guard let id = eventClips == nil ? event : eventClips?[event] else {
            message = "這套造型的這個動作尚未準備"; return
        }
        play(id, at: date)
    }

    func play(_ id: String, at date: Date = .now) {
        guard context.allowsMotion else { return }
        guard !isPlaying || currentClipID != id else { return }
        guard let clip = clips.first(where: { $0.id == id }) else { message = "這個動作尚未準備"; return }
        if let reason = unavailableReason(for: clip) { message = "\(clip.title)：\(reason)"; return }
        let prepared: PreparedClip
        do { prepared = try prepareClip(clip) }
        catch {
            failedClips[id] = "畫稿或輪廓資料讀取失敗"
            message = "\(clip.title)：畫稿或輪廓資料讀取失敗"; return
        }
        playTask?.cancel(); idleTask?.cancel()
        generation = UUID()
        let token = generation
        policy.didStart(id, at: date)
        if id == "yawn" { defaults.set(date.timeIntervalSince1970, forKey: Self.yawnKey) }
        currentClipID = id; isPlaying = true; anchor = prepared.anchor
        drawingScale = clip.scale; cellAspectRatio = prepared.aspectRatio; message = clip.title
        onClipStarted?(id)
        playTask = Task { @MainActor [weak self] in
            for index in 0..<clip.frameCount {
                guard let self, !Task.isCancelled, self.generation == token, self.context.allowsMotion else { return }
                do { self.image = try prepared.frame(at: index); self.frameIndex = index }
                catch {
                    self.failedClips[id] = "輪廓畫格無法顯示"
                    self.stop(); self.message = "\(clip.title)：輪廓畫格無法顯示"; return
                }
                do { try await Task.sleep(nanoseconds: UInt64(clip.durationsMs[index] * 1_000_000)) }
                catch { return }
            }
            guard let self, self.generation == token, !Task.isCancelled else { return }
            if self.restingClipID == id {
                self.restingImage = self.image; self.restingAnchor = self.anchor
                self.restingScale = self.drawingScale; self.restingAspectRatio = self.cellAspectRatio
            }
            self.isPlaying = false
            self.playTask = nil
            self.showRestingPose()
            self.message = "安靜陪著你"
            self.scheduleIdle()
        }
    }

    func stop() {
        generation = UUID(); playTask?.cancel(); idleTask?.cancel()
        playTask = nil; idleTask = nil; isPlaying = false
        showRestingPose()
    }

    func suspend() {
        var quiet = context
        quiet.active = false
        update(quiet)
    }

    private func showRestingPose() {
        image = restingImage; anchor = restingAnchor; drawingScale = restingScale
        cellAspectRatio = restingAspectRatio
        frameIndex = 0; currentClipID = nil
    }

    private func scheduleIdle() {
        idleTask?.cancel(); idleTask = nil
        guard context.allowsIdle, !isPlaying else { return }
        let mapped = idleClips ?? PatrickAnimationPolicy.idleIDs.compactMap { eventClips == nil ? $0 : eventClips?[$0] }
        let available = Array(Set(mapped)).sorted().filter { id in
            clips.first(where: { $0.id == id }).map { unavailableReason(for: $0) == nil } ?? false
        }
        let choices = policy.idleCandidates(from: available)
        // If only the previous idle exists, keep still instead of repeating it.
        guard !choices.isEmpty else { return }
        let delay = Double.random(in: PatrickAnimationPolicy.idleInterval)
        idleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, !Task.isCancelled, self.context.allowsIdle, !self.isPlaying,
                  let id = choices.randomElement() else { return }
            self.play(id)
        }
    }

    private func prepareClip(_ clip: PatrickAnimationClip) throws -> PreparedClip {
        guard clip.unavailableReason == nil, let path = clip.bundledAtlasPath, let root = resourceRoot else {
            throw PlaybackError.invalid("畫稿資料無效")
        }
        let png = try Data(contentsOf: root.appendingPathComponent(path))
        let pngHash = Self.sha256(png)
        if let expected = clip.sha256, pngHash != expected.lowercased() {
            throw PlaybackError.invalid("畫稿版本校驗失敗")
        }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
              atlas.width == clip.width, atlas.height == clip.height else {
            throw PlaybackError.invalid("畫稿尺寸或資料無效")
        }
        var regions: PatrickFrameRegions?
        if let reference = clip.frameRegions {
            // A declared sidecar is mandatory. No error path falls back to grid.
            guard let path = reference.bundledPath else { throw PlaybackError.invalid("輪廓資料路徑無效") }
            let data = try Data(contentsOf: root.appendingPathComponent(path))
            guard Self.sha256(data) == reference.sha256.lowercased() else { throw PlaybackError.invalid("輪廓資料版本校驗失敗") }
            let decoded = try JSONDecoder().decode(PatrickFrameRegions.self, from: data)
            guard decoded.unavailableReason(for: clip) == nil,
                  decoded.source.sha256.lowercased() == pngHash else { throw PlaybackError.invalid("輪廓來源或定位資料無效") }
            regions = decoded
        }
        return PreparedClip(clip: clip, atlas: atlas, regions: regions)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct PreparedClip {
        let clip: PatrickAnimationClip
        let atlas: CGImage
        let regions: PatrickFrameRegions?
        var anchor: [Double] { regions?.canvas.anchorNormalized ?? clip.anchorNormalized }
        var aspectRatio: Double { regions == nil ? clip.cellAspectRatio : 1 }

        func frame(at index: Int) throws -> CGImage {
            guard (0..<clip.frameCount).contains(index) else { throw PlaybackError.invalid("畫格編號無效") }
            if let regions {
                return try PatrickAnimationPlayer.renderRegion(atlas: atlas, frame: regions.frames[clip.sourceIndices[index]], canvas: regions.canvas)
            }
            guard let bounds = clip.pixelBounds(for: index),
                  let frame = atlas.cropping(to: CGRect(x: CGFloat(bounds.x), y: CGFloat(bounds.y), width: CGFloat(bounds.width), height: CGFloat(bounds.height))) else {
                throw PlaybackError.invalid("畫稿分格失敗")
            }
            return frame
        }

    }

    nonisolated static func renderRegion(atlas: CGImage, frame: PatrickFrameRegions.Frame, canvas: PatrickFrameRegions.Canvas) throws -> CGImage {
        let colorSpace = atlas.colorSpace?.model == .rgb ? atlas.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: canvas.width, height: canvas.height,
            bitsPerComponent: 8, bytesPerRow: canvas.width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw PlaybackError.invalid("輪廓畫布建立失敗")
        }
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(canvas.width), height: CGFloat(canvas.height)))
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        let mask = CGMutablePath()
        let tx = frame.translation[0], ty = frame.translation[1]
        // Metadata is top-left. Quartz bitmap space is bottom-left: convert
        // y once here and for the whole-atlas destination below, never flip
        // individual drawings. Every selected source pixel keeps a 1:1 size.
        for row in frame.rows {
            let destinationY = row[0] + ty
            for offset in stride(from: 1, to: row.count, by: 2) {
                mask.addRect(CGRect(x: CGFloat(row[offset] + tx),
                    y: CGFloat(canvas.height - destinationY - 1),
                    width: CGFloat(row[offset + 1] - row[offset]), height: 1))
            }
        }
        context.addPath(mask)
        context.clip()
        context.draw(atlas, in: CGRect(x: CGFloat(tx), y: CGFloat(canvas.height - ty - atlas.height),
            width: CGFloat(atlas.width), height: CGFloat(atlas.height)))
        guard let result = context.makeImage() else { throw PlaybackError.invalid("輪廓畫格建立失敗") }
        return result
    }

    private enum PlaybackError: Error { case invalid(String) }
}
