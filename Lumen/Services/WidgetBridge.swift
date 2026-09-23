import Foundation
import WidgetKit

/// Tells the home-screen widget that shared data changed.
enum WidgetBridge {
    static func reload() { WidgetCenter.shared.reloadAllTimelines() }
}
