import Foundation

/// Sibling WatchConnectivity payload. Older builds ignore this key.
/// It never changes theme, timer, or the face.
enum PatrickFieldTestPing {
    static let transportKey = "patrick.fieldtest.v1"

    struct Body: Codable, Equatable, Sendable {
        var id: UUID
        var sentAt: Date
        var role: String
        var system: String
        var note: String
    }

    static func encode(_ body: Body) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(body)
    }

    static func decode(_ data: Data) -> Body? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Body.self, from: data)
    }
}
