import CoreGraphics
import Foundation

struct AnchorManifest: Decodable {
    struct CoordinateSpace: Decodable {
        let width: Double
        let height: Double
        let origin: String
    }

    struct Mesh: Decodable {
        let bodyControlPoints: [[Double]]
    }

    let id: String
    let version: Int
    let coordinateSpace: CoordinateSpace
    let anchors: [String: [Double]]
    let mesh: Mesh

    func point(_ name: String, default fallback: CGPoint) -> CGPoint {
        guard let values = anchors[name], values.count == 2 else { return fallback }
        return CGPoint(x: values[0], y: values[1])
    }

    var bodyControlPoints: [CGPoint] {
        mesh.bodyControlPoints.compactMap { values in
            guard values.count == 2 else { return nil }
            return CGPoint(x: values[0], y: values[1])
        }
    }

    static func load() -> AnchorManifest {
        if let url = Bundle.main.url(
            forResource: "patrick-anchor-manifest.fallback",
            withExtension: "json"
        ),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AnchorManifest.self, from: data) {
            return decoded
        }
        return .fallback
    }

    static let fallback = AnchorManifest(
        id: "swift-embedded-fallback",
        version: 1,
        coordinateSpace: CoordinateSpace(width: 360, height: 440, origin: "top-left"),
        anchors: [
            "characterRoot": [180, 240],
            "hourArmPivot": [180, 240],
            "minuteArmPivot": [180, 240],
            "faceRoot": [180, 190],
            "leftEye": [158, 188],
            "rightEye": [202, 188],
            "shortsRoot": [180, 338]
        ],
        mesh: Mesh(bodyControlPoints: [
            [180, 92], [145, 131], [118, 219], [106, 309], [126, 338],
            [180, 348], [234, 338], [254, 309], [242, 219], [215, 131]
        ])
    )
}
