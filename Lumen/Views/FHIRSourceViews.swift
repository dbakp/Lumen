import SwiftUI

struct FHIRPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        LumenPrimaryButtonStyle().makeBody(configuration: configuration).opacity(enabled ? 1 : 0.4)
    }
}

struct FHIRReaderLink<Destination: View>: View {
    let title: String
    let destination: () -> Destination
    init(_ title: String, @ViewBuilder destination: @escaping () -> Destination) { self.title = title; self.destination = destination }
    var body: some View {
        NavigationLink { destination() } label: {
            HStack(alignment: .top, spacing: 16) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).padding(.top, 4).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).foregroundStyle(Theme.accent)
        }.buttonStyle(.plain)
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
    @State private var page = 0
    private var sections: [String] { FHIRSourceReading.pages(text) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("fhirTextTop")
                    if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                    pageControls
                    Text(sections[min(page, sections.count - 1)]).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier("fhirFullText")
                    if sections.count > 1 { Text("Complete text continues across these parts. A long token may cross a part boundary.").font(.footnote).foregroundStyle(Theme.secondary) }
                    if sections.count > 1 { pageControls }
                }.padding(Theme.gutter)
            }.lumenScreen().onChange(of: page) { _, _ in proxy.scrollTo("fhirTextTop", anchor: .top) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
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
                            FHIRTextReader(title: "Original field", text: field.token, subtitle: field.path + "\nOriginal UTF-8 bytes \(field.byteStart)–\(field.byteEnd - 1), starting at zero.")
                        } label: {
                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(field.path).fixedSize(horizontal: false, vertical: true).foregroundStyle(Theme.accent)
                                    Text("Read complete field · \(field.token.count.formatted()) \(field.token.count == 1 ? "character" : "characters")").font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).padding(.top, 4).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain).accessibilityIdentifier("fhirOriginalField-\(index)")
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
        return values
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("fhirCoverageTop")
                    ForEach(Array(items.enumerated().dropFirst(page * 10).prefix(10)), id: \.offset) { _, value in
                        FHIRReaderLink(LabTable.displayPreview(value, maxCharacters: 200).text) { FHIRTextReader(title: "Coverage detail", text: value) }
                        Divider()
                    }
                    LabHistoryPager(page: page, count: items.count, size: 10) { page = $0 }
                }.padding(Theme.gutter)
            }.lumenScreen().onChange(of: page) { _, _ in proxy.scrollTo("fhirCoverageTop", anchor: .top) }
        }.navigationTitle("File coverage details").navigationBarTitleDisplayMode(.inline)
    }
}
