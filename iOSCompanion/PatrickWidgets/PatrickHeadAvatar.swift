import SwiftUI
import WidgetKit

enum PatrickHeadSlot {
    case circular
    case rectangular
    case corner
    case activity

    var imageBase: String {
        switch self {
        case .circular: "PatrickHeadCircular"
        case .rectangular: "PatrickHeadRectangular"
        case .corner: "PatrickHeadCorner"
        case .activity: "PatrickHeadActivity"
        }
    }
}

/// Head cropped from the season-1 flat body already in the watch catalog.
/// Accented and tinted widgets tint the skin mask and keep the face marks
/// in the light group. Full colour and vibrant mode use the colour bitmap.
struct PatrickHeadAvatar: View {
    var slot: PatrickHeadSlot
    var side: CGFloat? = nil
    var decorative: Bool = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        avatar
            .frame(width: side, height: side)
            .accessibilityLabel("派大星")
            .accessibilityHidden(decorative)
    }

    @ViewBuilder private var avatar: some View {
        switch renderingMode {
        case .accented:
            ZStack {
                image("Skin").widgetAccentable()
                image("Features").widgetAccentable(false)
            }
        default:
            image("").widgetAccentable(false)
        }
    }

    private func image(_ suffix: String) -> some View {
        Image(slot.imageBase + suffix)
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
    }
}
