import SwiftUI

struct SettingsSaveFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let retry: () -> Void

    init(_ setting: String, error: Error, retainedDraft: Bool = false, retry: @escaping () -> Void) {
        title = "Couldn’t save \(setting)"
        let next: String
        if let error = error as? BackupError, case .busy = error {
            next = "Health is syncing. Wait for it to finish, then try again."
        } else if let error = error as? BackupError, case .recordsChanged = error {
            next = "Other records changed while saving. Try again."
        } else if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileWriteOutOfSpaceError {
            next = "Storage is full. Free some space on this iPhone, then try again."
        } else { next = "Try again." }
        message = (retainedDraft ? "Your edit is still here. " : "This change wasn’t applied. ") + next
        self.retry = retry
    }
}

extension View {
    func settingsSaveAlert(_ failure: Binding<SettingsSaveFailure?>) -> some View {
        alert(item: failure) { value in
            Alert(title: Text(value.title), message: Text(value.message),
                  primaryButton: .default(Text("Try again"), action: value.retry),
                  secondaryButton: .cancel(Text("Not now")))
        }
    }
}
