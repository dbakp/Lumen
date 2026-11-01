import SwiftUI

/// Presented by the view that owns the draft, including when that view is a sheet.
struct LocalSaveFailure: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static func saving(_ noun: String, error: Error, draft: Bool = false) -> Self {
        let detail: String
        if let error = error as? BackupError, case .recordsChanged = error {
            detail = "Other records changed while saving. Try saving again."
        } else if let error = error as? BackupError, case .busy = error {
            detail = "Health is syncing. Wait for it to finish, then try saving again."
        } else if (error as NSError).code == NSFileWriteOutOfSpaceError {
            detail = "Storage is full. Free some space on this iPhone, then try again."
        } else { detail = "Try saving again." }
        return .init(title: "Couldn’t save \(noun)", message: (draft ? "Your \(noun) is still here. " : "") + detail)
    }
    static func removing(_ noun: String) -> Self {
        .init(title: "Couldn’t remove \(noun)", message: "Your \(noun) is still saved. Try again.")
    }
}

extension View {
    func localSaveAlert(_ failure: Binding<LocalSaveFailure?>) -> some View {
        alert(item: failure) { value in
            Alert(title: Text(value.title), message: Text(value.message), dismissButton: .default(Text("OK")))
        }
    }
}
