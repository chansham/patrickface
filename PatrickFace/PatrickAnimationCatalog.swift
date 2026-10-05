import Foundation

/// Shared animation/catalog.json. Unknown fields are intentionally ignored.
struct PatrickAnimationCatalog: Decodable, Sendable {
    let clips: [PatrickAnimationClip]
    let master: PatrickAnimationRegistration?
}

struct PatrickAnimationRegistration: Decodable, Sendable {
    let anchorNormalized: [Double]
}

struct PatrickAnimationClip: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let category: String
    let atlas: String?
    let columns: Int
    let rows: Int
    let frameCount: Int
    let width: Int
    let height: Int
    let durationsMs: [Double]
    let anchorNormalized: [Double]
    let frameIndices: [Int]?
    let approvedDirection: Bool
    let scale: Double
    let sha256: String?
    let frameRegions: PatrickFrameRegionsReference?

    private enum CodingKeys: String, CodingKey {
        case id, title, category, atlas, columns, rows, frameCount, width, height
        case durationsMs, anchorNormalized, frameIndices, approvedDirection, scale, sha256, frameRegions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "scene"
        atlas = try values.decodeIfPresent(String.self, forKey: .atlas)
        columns = try values.decodeIfPresent(Int.self, forKey: .columns) ?? 0
        rows = try values.decodeIfPresent(Int.self, forKey: .rows) ?? 0
        frameCount = try values.decodeIfPresent(Int.self, forKey: .frameCount) ?? 0
        width = try values.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try values.decodeIfPresent(Int.self, forKey: .height) ?? 0
        durationsMs = try values.decodeIfPresent([Double].self, forKey: .durationsMs) ?? []
        anchorNormalized = try values.decodeIfPresent([Double].self, forKey: .anchorNormalized) ?? [0.5, 0.5]
        frameIndices = try values.decodeIfPresent([Int].self, forKey: .frameIndices)
        approvedDirection = try values.decodeIfPresent(Bool.self, forKey: .approvedDirection) ?? false
        scale = try values.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        sha256 = try values.decodeIfPresent(String.self, forKey: .sha256)
        frameRegions = try values.decodeIfPresent(PatrickFrameRegionsReference.self, forKey: .frameRegions)
    }

    var sourceIndices: [Int] { frameIndices ?? Array(0..<max(0, frameCount)) }

    var cellAspectRatio: Double {
        if frameRegions != nil { return 1 }
        guard columns > 0, rows > 0, width > 0, height > 0 else { return 1 }
        return (Double(width) / Double(columns)) / (Double(height) / Double(rows))
    }

    var bundledAtlasPath: String? {
        PatrickAnimationPaths.bundledRelativePath(atlas)
    }

    var unavailableReason: String? {
        guard bundledAtlasPath != nil else { return "畫稿尚未準備" }
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              frameCount > 0, frameCount <= 256 else { return "分格資料不完整" }
        guard durationsMs.count == frameCount,
              durationsMs.allSatisfy({ $0.isFinite && $0 >= 16 && $0 <= 30_000 }),
              durationsMs.reduce(0, +) <= 120_000 else { return "播放時間資料不完整" }
        guard sourceIndices.count == frameCount, sourceIndices.allSatisfy({ $0 >= 0 }) else { return "畫稿順序無效" }
        if let regions = frameRegions {
            guard regions.version == 1, regions.bundledPath != nil,
                  PatrickAnimationPaths.isSHA256(regions.sha256) else { return "輪廓資料索引無效" }
        } else {
            guard columns > 0, rows > 0, columns <= 64, rows <= 64,
                  width >= columns, height >= rows,
                  sourceIndices.allSatisfy({ $0 < columns * rows }) else { return "分格資料不完整" }
        }
        guard anchorNormalized.count == 2,
              anchorNormalized.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return "角色定位無效" }
        guard scale.isFinite, (0.1...4).contains(scale) else { return "角色比例無效" }
        return nil
    }

    /// Round shared fractional grid boundaries once; do not accumulate cell widths.
    func pixelBounds(for playbackIndex: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard frameRegions == nil, unavailableReason == nil, (0..<frameCount).contains(playbackIndex) else { return nil }
        let source = sourceIndices[playbackIndex]
        let column = source % columns, row = source / columns
        let x = Int((Double(column) * Double(width) / Double(columns)).rounded())
        let right = Int((Double(column + 1) * Double(width) / Double(columns)).rounded())
        let y = Int((Double(row) * Double(height) / Double(rows)).rounded())
        let bottom = Int((Double(row + 1) * Double(height) / Double(rows)).rounded())
        return (x, y, right - x, bottom - y)
    }
}

enum PatrickAnimationPaths {
    static func bundledRelativePath(_ raw: String?) -> String? {
        guard var path = raw, !path.isEmpty else { return nil }
        if path.hasPrefix("animation/") { path.removeFirst("animation/".count) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.contains(":"), !path.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return path
    }

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
}

struct PatrickFrameRegionsReference: Decodable, Sendable {
    let path: String
    let sha256: String
    let version: Int
    var bundledPath: String? { PatrickAnimationPaths.bundledRelativePath(path) }
}

struct PatrickFrameRegions: Decodable, Sendable {
    struct Source: Decodable, Sendable {
        let path: String
        let sha256: String
        let width: Int
        let height: Int
    }
    struct Canvas: Decodable, Sendable {
        let width: Int
        let height: Int
        let anchorPixels: [Int]
        let anchorNormalized: [Double]
    }
    struct Frame: Decodable, Sendable {
        let sourceBounds: [Int]
        let anchorSource: [Int]
        let placement: [Int]
        let translation: [Int]
        let rows: [[Int]]
    }
    let schemaVersion: Int
    let source: Source
    let canvas: Canvas
    let frames: [Frame]

    func unavailableReason(for clip: PatrickAnimationClip) -> String? {
        guard clip.unavailableReason == nil else { return "動作索引無效" }
        guard schemaVersion == 1, source.width == clip.width, source.height == clip.height,
              PatrickAnimationPaths.bundledRelativePath(source.path) == clip.bundledAtlasPath,
              PatrickAnimationPaths.isSHA256(source.sha256) else { return "輪廓來源不符" }
        if let expected = clip.sha256, source.sha256.lowercased() != expected.lowercased() { return "輪廓來源版本不符" }
        guard canvas.width > 0, canvas.width == canvas.height, canvas.width <= 8192,
              canvas.anchorPixels.count == 2, canvas.anchorNormalized.count == 2,
              canvas.anchorPixels.allSatisfy({ (0...canvas.width).contains($0) }),
              canvas.anchorNormalized.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return "輪廓畫布無效" }
        for axis in 0..<2 {
            guard abs(canvas.anchorNormalized[axis] - Double(canvas.anchorPixels[axis]) / Double(canvas.width)) < 0.000001 else { return "輪廓定位比例不符" }
        }
        guard !frames.isEmpty, frames.count <= 256,
              clip.sourceIndices.allSatisfy({ $0 >= 0 && $0 < frames.count }) else { return "輪廓畫格順序無效" }
        for frame in frames {
            guard frame.sourceBounds.count == 4, frame.anchorSource.count == 2,
                  frame.placement.count == 2, frame.translation.count == 2 else { return "輪廓畫格資料不完整" }
            let b = frame.sourceBounds, p = frame.placement, t = frame.translation
            guard b[0] >= 0, b[1] >= 0, b[2] > 0, b[3] > 0,
                  b[2] <= source.width, b[3] <= source.height,
                  b[0] <= source.width - b[2], b[1] <= source.height - b[3],
                  p[0] >= 0, p[1] >= 0, b[2] <= canvas.width, b[3] <= canvas.height,
                  p[0] <= canvas.width - b[2], p[1] <= canvas.height - b[3],
                  frame.anchorSource[0] >= b[0], frame.anchorSource[0] <= b[0] + b[2],
                  frame.anchorSource[1] >= b[1], frame.anchorSource[1] <= b[1] + b[3] else { return "輪廓畫格超出邊界" }
            for axis in 0..<2 {
                // Subtraction uses already bounded coordinates, avoiding Int overflow.
                guard t[axis] == canvas.anchorPixels[axis] - frame.anchorSource[axis],
                      t[axis] == p[axis] - b[axis] else { return "輪廓平移與定位不一致" }
            }
            guard !frame.rows.isEmpty, frame.rows.count <= b[3] else { return "輪廓像素列缺失" }
            var previousY = b[1] - 1
            for row in frame.rows {
                guard row.count >= 3, row.count % 2 == 1,
                      row[0] > previousY, row[0] >= b[1], row[0] < b[1] + b[3] else { return "輪廓像素列無效" }
                var previousEnd = b[0]
                for offset in stride(from: 1, to: row.count, by: 2) {
                    let start = row[offset], end = row[offset + 1]
                    guard start >= previousEnd, start < end, end <= b[0] + b[2] else { return "輪廓像素範圍無效" }
                    previousEnd = end
                }
                previousY = row[0]
            }
        }
        return nil
    }
}
