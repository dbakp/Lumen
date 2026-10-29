import SwiftUI
import UIKit

/// Preserve SwiftUI's presentation callbacks while intercepting an edited draft's swipe dismissal.
struct SheetDismissGuard: UIViewControllerRepresentable {
    let hasEdits: Bool
    let onAttempt: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> GuardController { GuardController() }
    func updateUIViewController(_ controller: GuardController, context: Context) {
        context.coordinator.hasEdits = hasEdits
        context.coordinator.onAttempt = onAttempt
        controller.install = { [weak controller, weak coordinator = context.coordinator] in
            guard let controller, let coordinator else { return }
            var owner: UIViewController = controller
            while let parent = owner.parent { owner = parent }
            guard let presentation = owner.presentationController else { return }
            if presentation.delegate !== coordinator { coordinator.previous = presentation.delegate; presentation.delegate = coordinator }
        }
        controller.install?()
    }
    static func dismantleUIViewController(_ controller: GuardController, coordinator: Coordinator) {
        var owner: UIViewController = controller
        while let parent = owner.parent { owner = parent }
        if let presentation = owner.presentationController, presentation.delegate === coordinator { presentation.delegate = coordinator.previous }
        coordinator.previous = nil
    }
    final class GuardController: UIViewController {
        var install: (() -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); install?() }
        override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); install?() }
    }
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var previous: UIAdaptivePresentationControllerDelegate?
        var hasEdits = false
        var onAttempt: () -> Void = {}
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            !hasEdits && (previous?.presentationControllerShouldDismiss?(presentationController) ?? true)
        }
        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            if hasEdits { onAttempt() }
            else { previous?.presentationControllerDidAttemptToDismiss?(presentationController) }
        }
        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) { previous?.presentationControllerWillDismiss?(presentationController) }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { previous?.presentationControllerDidDismiss?(presentationController) }
    }
}
