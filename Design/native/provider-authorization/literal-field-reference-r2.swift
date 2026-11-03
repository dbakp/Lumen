// Standalone diagnostic, excluded from the Lumen application target.
import SwiftUI
import UIKit

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
    private let largest = ProcessInfo.processInfo.arguments.contains("--largest")
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("iOS client ID").font(.caption).foregroundStyle(.secondary)
                    CharacterWrappedInput(value: $value, largest: largest)
                }
            }
            .navigationTitle("Character wrapping").navigationBarTitleDisplayMode(.inline)
        }
        .dynamicTypeSize(largest ? .accessibility5 : .large)
    }
}

private struct CharacterWrappedInput: UIViewRepresentable {
    @Binding var value: String
    let largest: Bool
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byCharWrapping
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.accessibilityIdentifier = "literalReferenceInput"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let category: UIContentSizeCategory = largest ? .accessibilityExtraExtraExtraLarge : .large
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.hyphenationFactor = 0
        view.attributedText = NSAttributedString(string: value, attributes: [
            .font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph
        ])
        view.typingAttributes = [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
