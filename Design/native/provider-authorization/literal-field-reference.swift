// Standalone renderer comparison; excluded from the Lumen application target.
import SwiftUI

@main
struct LiteralFieldReference: App {
    var body: some Scene { WindowGroup { LiteralRoot() } }
}

private struct LiteralRoot: View {
    @State private var showing = false
    var body: some View {
        Text("Literal field reference")
            .sheet(isPresented: $showing) { LiteralEditor() }
            .task { showing = true }
    }
}

private struct LiteralEditor: View {
    @State private var value = "123456789-synthetic42.apps.googleusercontent.com"
    private let args = ProcessInfo.processInfo.arguments
    private var variant: String {
        args.contains("--nonlinguistic") ? "Nonlinguistic" : args.contains("--undefined") ? "Undefined" : args.contains("--monospace") ? "Monospaced" : "Native"
    }
    private var input: some View {
        TextField("iOS client ID", text: $value, axis: .vertical)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .font(args.contains("--monospace") ? .system(.body, design: .monospaced) : .body)
            .accessibilityIdentifier("literalReferenceInput")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("iOS client ID").font(.caption).foregroundStyle(.secondary)
                    if args.contains("--nonlinguistic") {
                        input.typesettingLanguage(Locale.Language(identifier: "zxx"))
                    } else if args.contains("--undefined") {
                        input.typesettingLanguage(Locale.Language(identifier: "und"))
                    } else { input }
                }
            }
            .navigationTitle(variant).navigationBarTitleDisplayMode(.inline)
        }
        .dynamicTypeSize(args.contains("--largest") ? .accessibility5 : .large)
    }
}
