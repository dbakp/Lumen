import Foundation

/// Routes lumen:// links (from widgets) to a tab or sheet.
@MainActor
public final class DeepLink: ObservableObject {
    public static let shared = DeepLink()
    public enum Target: Equatable { case today, activity, snap, sleep, coach }
    @Published public var pending: Target?

    public func handle(_ url: URL) {
        guard url.scheme == "lumen" else { return }
        switch url.host {
        case "today": pending = .today
        case "activity": pending = .activity
        case "snap": pending = .snap
        case "sleep": pending = .sleep
        case "coach": pending = .coach
        default: break
        }
    }
}
