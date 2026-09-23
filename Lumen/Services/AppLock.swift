import SwiftUI
import LocalAuthentication

// MARK: - Optional Face ID lock (health data is personal)

@MainActor
public final class AppLock: ObservableObject {
    public static let shared = AppLock()
    @Published public private(set) var isLocked = false
    private var backgroundedAt: Date?

    public var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        switch ctx.biometryType { case .faceID: return "Face ID"; case .touchID: return "Touch ID"; case .opticID: return "Optic ID"; default: return "Passcode" }
    }

    public var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    public func handle(phase: ScenePhase, enabled: Bool, coldStart: Bool = false) {
        guard enabled else { isLocked = false; return }
        switch phase {
        case .background:
            backgroundedAt = Date()
        case .active:
            // Re-lock after 60 s away (or on a cold start).
            if coldStart || (backgroundedAt.map { Date().timeIntervalSince($0) > 60 } ?? false) {
                isLocked = true
                Task { await unlock() }
            }
            backgroundedAt = nil
        default: break
        }
    }

    public func unlock() async {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your Lumen data") {
                isLocked = false
            }
        } catch { /* stay locked; user can retry */ }
    }

    /// Verify before enabling so nobody locks themselves out.
    public func verify() async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on app lock")) ?? false
    }
}

struct LockScreen: View {
    @ObservedObject var lock = AppLock.shared
    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 18) {
                LumenOrb(size: 140)
                Text("Lumen is locked").font(.title2.weight(.bold)).foregroundStyle(.white)
                Button { Task { await lock.unlock() } } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                }
                .buttonStyle(LumenPrimaryButtonStyle())
                .padding(.horizontal, 40)
            }
        }
    }
}
