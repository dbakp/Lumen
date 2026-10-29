import SwiftUI

struct DocumentBodyView: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DocumentBlocks.parse(text)) { block in
                switch block.kind {
                case .heading(let level):
                    Text(block.text).font(level == 1 ? .title2.bold() : .title3.bold())
                        .padding(.top, 12).accessibilityAddTraits(.isHeader)
                case .paragraph:
                    Text(inline(block.text)).font(.body).lineSpacing(5)
                case .listItem(let marker):
                    HStack(alignment: .top, spacing: 12) {
                        Text(marker).foregroundStyle(Theme.secondary)
                        Text(inline(block.text)).font(.body).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityElement(children: .combine)
                case .code:
                    Text(block.text).font(.system(.footnote, design: .monospaced)).padding(12).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
