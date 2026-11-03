// Standalone simulator diagnostic. Not part of the Lumen application target.
// No stores, credentials, network requests, custom sizing or app theme.
import SwiftUI

@main
struct LumenKeyboardReference: App {
    var body: some Scene { WindowGroup { ReferenceRoot() } }
}

private struct ReferenceRoot: View {
    @State private var showing = false
    var body: some View {
        Button("Open reference editor") { showing = true }
            .sheet(isPresented: $showing) { ReferenceEditor() }
            .task { showing = true }
    }
}

private struct ReferenceEditor: View {
    @State private var text = "Reference input"
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                if ProcessInfo.processInfo.arguments.contains("--secure-reference") {
                    SecureField("Reference input", text: $text)
                        .focused($focused)
                        .accessibilityIdentifier("referenceInput")
                } else {
                    TextField("Reference input", text: $text)
                        .focused($focused)
                        .accessibilityIdentifier("referenceInput")
                }
            }
            .navigationTitle("Keyboard reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Done") { focused = false }
                }
            }
            .task { focused = true }
        }
    }
}
