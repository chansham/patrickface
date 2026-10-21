import AppIntents
import Foundation

enum PatrickMindChoice: String, AppEnum {
    case veryPleasant, pleasant, neutral, unpleasant, veryUnpleasant
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "我的心情")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .veryPleasant: "很愉快", .pleasant: "愉快", .neutral: "平靜",
        .unpleasant: "不太好", .veryUnpleasant: "很難過"
    ]
    var title: String {
        switch self {
        case .veryPleasant: "很愉快"
        case .pleasant: "愉快"
        case .neutral: "平靜"
        case .unpleasant: "不太好"
        case .veryUnpleasant: "很難過"
        }
    }
}

/// Installed from Settings → Focus. While this filter is on, proactive haptics
/// and notification sounds stay quiet. No extra entitlement.
@available(iOS 16.0, watchOS 9.0, *)
struct PatrickFocusFilterIntent: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "派大星安靜"
    static var description = IntentDescription("這個專注模式開啟時，派大星不主動震動，倒數也不出聲。")

    @Parameter(title: "保持安靜", default: true)
    var quiet: Bool

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "派大星安靜") }

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(quiet, forKey: PatrickFocusFilterIntent.storageKey)
        return .result()
    }

    static let storageKey = "patrick.focus-filter.quiet"

    static func refreshStoredFlag() async -> Bool {
        if #available(iOS 16.0, watchOS 9.0, *) {
            if let current = try? await PatrickFocusFilterIntent.current {
                let active = current.quiet
                UserDefaults.standard.set(active, forKey: storageKey)
                return active
            }
        }
        UserDefaults.standard.set(false, forKey: storageKey)
        return false
    }
}
