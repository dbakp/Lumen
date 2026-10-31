import SwiftUI
import UIKit

/// Literal source text must wrap without adding discretionary punctuation.
/// Keep UIKit's native read-only text selection; this is not an editor bridge.
private struct FHIRLiteralText: UIViewRepresentable {
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    final class Coordinator: NSObject, NSLayoutManagerDelegate {
        func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool { false }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.dataDetectorTypes = []; view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        view.layoutManager.usesDefaultHyphenation = false
        view.layoutManager.delegate = context.coordinator
        view.adjustsFontForContentSizeCategory = true
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "fhirFullText"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let value = FHIRLiteralTypography.value(text, size: typeSize, color: UIColor(Theme.text), wrapping: .byWordWrapping)
        if view.attributedText?.isEqual(to: value) != true {
            let range = view.selectedRange
            view.attributedText = value
            let start = min(range.location, value.length)
            view.selectedRange = NSRange(location: start, length: min(range.length, value.length - start))
        }
        view.accessibilityLabel = text
        view.accessibilityIdentifier = "fhirFullText"
        view.tintColor = UIColor(Theme.accent)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

/// Navigation previews cannot intercept the source action for text selection.
/// The destination provides selectable complete text with the same wrapping.
private struct FHIRLiteralLabel: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var color: Color = Theme.accent
    var exposed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    func makeUIView(context: Context) -> UILabel {
        let view = UILabel()
        view.numberOfLines = 0; view.adjustsFontSizeToFitWidth = false
        view.lineBreakMode = .byCharWrapping
        view.adjustsFontForContentSizeCategory = true; view.isUserInteractionEnabled = false
        view.isAccessibilityElement = exposed
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UILabel, context: Context) {
        view.attributedText = FHIRLiteralTypography.value(text, size: typeSize, color: UIColor(color), style: style)
        view.isAccessibilityElement = exposed
        view.accessibilityLabel = text
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }
}

private enum FHIRLiteralTypography {
    static func value(_ text: String, size: DynamicTypeSize, color: UIColor, style: UIFont.TextStyle = .body, wrapping: NSLineBreakMode = .byCharWrapping) -> NSAttributedString {
        let category: UIContentSizeCategory
        switch size {
        case .xSmall: category = .extraSmall
        case .small: category = .small
        case .medium: category = .medium
        case .large: category = .large
        case .xLarge: category = .extraLarge
        case .xxLarge: category = .extraExtraLarge
        case .xxxLarge: category = .extraExtraExtraLarge
        case .accessibility1: category = .accessibilityMedium
        case .accessibility2: category = .accessibilityLarge
        case .accessibility3: category = .accessibilityExtraLarge
        case .accessibility4: category = .accessibilityExtraExtraLarge
        case .accessibility5: category = .accessibilityExtraExtraExtraLarge
        @unknown default: category = .large
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = wrapping
        paragraph.lineBreakStrategy = []
        paragraph.hyphenationFactor = 0; paragraph.usesDefaultHyphenation = false
        let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}

struct FHIRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        LumenPrimaryButtonStyle().makeBody(configuration: configuration).opacity(enabled ? 1 : 0.4)
    }
}

struct FHIRReaderLink<Destination: View>: View {
    let title: String
    let literal: Bool
    let destination: () -> Destination
    init(_ title: String, literal: Bool = false, @ViewBuilder destination: @escaping () -> Destination) { self.title = title; self.literal = literal; self.destination = destination }
    var body: some View {
        NavigationLink { destination() } label: {
            HStack(alignment: .top, spacing: 16) {
                if literal { FHIRLiteralLabel(text: title).frame(maxWidth: .infinity, alignment: .leading) }
                else { Text(title).fixedSize(horizontal: false, vertical: true) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).padding(.top, 4).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()).foregroundStyle(Theme.accent)
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

enum FHIRValueForm {
    static func label(_ kind: String) -> String {
        switch kind {
        case "valueQuantity": return "Quantity"
        case "valueCodeableConcept": return "Coded result"
        case "valueString": return "Text"
        case "valueBoolean": return "True or false"
        case "valueInteger": return "Whole number"
        case "valueRange": return "Range"
        case "valueRatio": return "Ratio"
        case "valueSampledData": return "Sampled data"
        case "valueTime": return "Time"
        case "valueDateTime": return "Date and time"
        case "valuePeriod": return "Period"
        case "dataAbsentReason": return "Missing-value reason"
        case "missing": return "No value reported"
        default: return kind
        }
    }
}

struct FHIRResultProvenanceView: View {
    let source: FHIRResultSource
    var identifier = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Original result type: " + FHIRValueForm.label(source.valueKind)).font(.footnote).foregroundStyle(Theme.secondary)
            if !source.permitsScalar { Text("Kept as wording").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary) }
            if let original = source.originalScalarToken { Text("Original number text: " + original).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            FHIRReaderLink("Original FHIR fields") { FHIRSourceFieldsView(fields: source.fields) }.accessibilityIdentifier(identifier)
        }
    }
}

/// Complete bounded paging; an unbroken JSON token is never ellipsized.
struct FHIRTextReader: View {
    let title: String
    let text: String
    var subtitle = ""
    var literalPath = ""
    @State private var page = 0
    @State private var copied = false
    private var sections: [String] { FHIRSourceReading.pages(text) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("fhirTextTop")
                    if !literalPath.isEmpty {
                        FHIRLiteralLabel(text: literalPath, style: .footnote, color: Theme.secondary, exposed: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    pageControls
                    FHIRLiteralText(text: sections[min(page, sections.count - 1)]).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("fhirFullText")
                    if sections.count > 1 { Text("Complete text continues across these parts. A long token may cross a part boundary.").font(.footnote).foregroundStyle(Theme.secondary) }
                    if sections.count > 1 { pageControls }
                }.padding(Theme.gutter)
            }.lumenScreen().onChange(of: page) { _, _ in proxy.scrollTo("fhirTextTop", anchor: .top) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "Copied full text" : "Copy full text", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = text; copied = true
                    }.labelStyle(.iconOnly).accessibilityIdentifier("copyFHIRText")
                }
            }.sensoryFeedback(.success, trigger: copied)
    }
    @ViewBuilder private var pageControls: some View {
        if sections.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Part \(page + 1) of \(sections.count)").font(.footnote).foregroundStyle(Theme.secondary)
                HStack {
                    Button("Previous") { page = max(0, page - 1) }.disabled(page == 0).accessibilityIdentifier("historyPreviousPage")
                    Spacer()
                    Button("Next") { page = min(sections.count - 1, page + 1) }.disabled(page == sections.count - 1).accessibilityIdentifier("historyNextPage")
                }.buttonStyle(.bordered)
            }
        }
    }
}

struct FHIRSourceFieldsView: View {
    let fields: [FHIRSourceField]
    @State private var page = 0
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Color.clear.frame(height: 1).id("fhirFieldsTop")
                    Text("Original JSON paths and tokens. Historical source fields stay separate from corrected review text.").font(.subheadline).foregroundStyle(Theme.secondary)
                    ForEach(Array(fields.enumerated().dropFirst(page * 10).prefix(10)), id: \.offset) { index, field in
                        NavigationLink {
                            FHIRTextReader(title: "Original field", text: field.token, subtitle: "Original UTF-8 bytes \(field.byteStart)–\(field.byteEnd - 1), starting at zero.", literalPath: field.path)
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    FHIRLiteralLabel(text: field.path).frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Read complete field · \(field.token.count.formatted()) \(field.token.count == 1 ? "character" : "characters")").font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).padding(.top, 4).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("fhirOriginalField-\(index)").accessibilityLabel(field.path + ", Read complete field · \(field.token.count.formatted()) \(field.token.count == 1 ? "character" : "characters")")
                        Divider()
                    }
                    LabHistoryPager(page: page, count: fields.count, size: 10) { page = $0 }
                }.padding(Theme.gutter)
            }.lumenScreen().onChange(of: page) { _, _ in proxy.scrollTo("fhirFieldsTop", anchor: .top) }
        }.navigationTitle("Original FHIR fields").navigationBarTitleDisplayMode(.inline)
    }
}

struct FHIRCoverageView: View {
    let preparation: FHIRLabPreparation
    @State private var page = 0
    private var items: [String] {
        var values = preparation.archive.entries.map { entry in
            let resource = entry.resourcePath.flatMap { preparation.archive.resource(at: $0) }
            return "Entry: " + (entry.path.isEmpty ? "file root" : entry.path) + "\nResource: " + (resource?.type ?? "request/response only") + (entry.requestMethod.map { "\nRequest method: " + $0 } ?? "")
        }
        values += preparation.archive.resources.map { resource in
            "Resource: " + resource.type + "\nPath: " + (resource.id.isEmpty ? "file root" : resource.id) + "\nFull URL: " + (resource.fullURL ?? "not supplied") + "\nVersion: " + (resource.version ?? "not supplied") + "\nContained in: " + (resource.container ?? "not contained")
        }
        values += preparation.coverage.panelsWithoutOwnValue.map { "Panel without its own result value\n" + $0 }
        values += preparation.coverage.links.map { link in
            let state: String
            switch link.resolution {
            case .found(let path): state = "Resolved locally to " + (path.isEmpty ? "file root" : path)
            case .missing: state = "Target not in this file"
            case .ambiguous(let paths): state = "Ambiguous local matches: " + paths.joined(separator: ", ")
            case .wrongType(let type): state = "Unexpected resource type: " + type
            case .unsupported: state = "No supported local reference identity"
            case .invalid: state = "Malformed reference"
            }
            return "Result link: " + link.fieldPath + "\n" + state + "\nOriginal: " + link.original.token
        }
        values += preparation.coverage.omittedResourceFields.sorted { $0.key < $1.key }.map { path, fields in
            "Fields not retained in full: " + (path.isEmpty ? "file root" : path) + "\n" + fields.joined(separator: "\n")
        }
        if preparation.archive.format == .ndjson {
            values.insert("Format: FHIR R4 NDJSON\n\n/line/N means physical line N, starting at 1. The rest of the path identifies a field on that line.\n\nOnly this local file was read. Companion files were not loaded. A resource ID in this file does not identify its original server.", at: 0)
        }
        return values
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("fhirCoverageTop")
                    ForEach(Array(items.enumerated().dropFirst(page * 10).prefix(10)), id: \.offset) { _, value in
                        FHIRReaderLink(LabTable.displayPreview(value, maxCharacters: 200).text, literal: true) { FHIRTextReader(title: "Coverage detail", text: value) }
                        Divider()
                    }
                    LabHistoryPager(page: page, count: items.count, size: 10) { page = $0 }
                }.padding(Theme.gutter)
            }.lumenScreen().onChange(of: page) { _, _ in proxy.scrollTo("fhirCoverageTop", anchor: .top) }
        }.navigationTitle("File coverage details").navigationBarTitleDisplayMode(.inline)
    }
}
