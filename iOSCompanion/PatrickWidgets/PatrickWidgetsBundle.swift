import SwiftUI
import WidgetKit

@main
struct PatrickWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PatrickStatusWidget()
        PatrickLiveActivity()
        PatrickFieldTestLiveActivity()
        PatrickFieldTestStandByWidget()
        if #available(iOS 18.0, *) {
            PatrickFieldTestToggleControl()
            PatrickFieldTestStartControl()
        }
    }
}
