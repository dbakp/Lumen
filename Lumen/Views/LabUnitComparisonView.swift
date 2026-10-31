import SwiftUI

struct LabUnitReviewFields: View {
    let first: LabHistory.Point
    let second: LabHistory.Point
    let chronological: Bool
    @Binding var review: LabNormalizationReview
    @State private var editing: CodeField?
    @Environment(\.dynamicTypeSize) private var size
    private enum CodeField: String, Identifiable { case first, second, target; var id: String { rawValue } }
    private var shared: [LabTestCode] { LabNormalization.sharedCodes(first, second) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Check the units.").font(.title2.bold())
            Text("Each code applies only to this comparison. Reported values and reference wording stay unchanged.").foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            unit(first, label: chronological ? "Earlier unit" : "First unit", field: .first)
            Divider()
            unit(second, label: chronological ? "Later unit" : "Second unit", field: .second)
            Divider()
            Text("Common unit").font(.headline)
            LabTextEditButton(text: review.targetCode, title: "Common UCUM code", identifier: "normalizationTarget") { editing = .target }
            if let issue = unitIssue(review.targetCode) { Text(issue).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            Text("Case matters. A printed micro sign uses u in UCUM. Check each assignment against the original report.").font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            FHIRReaderLink("Supported conversions") { FHIRTextReader(title: "Supported conversions", text: Self.supportedText) }.accessibilityIdentifier("normalizationSupported")
            Divider()
            Text("Match the test").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Text("Test identity").font(.subheadline)
                testMatchControl
            }
            if review.testMatch == .originalCoding {
                if shared.count > 1 {
                    Picker("Supplied code", selection: Binding(get: { review.testCode?.id ?? "" }, set: { key in review.testCode = shared.first { $0.id == key }; review.testChecked = false })) {
                        Text("Choose a code").tag("")
                        ForEach(shared, id: \.id) { code in Text(LabTable.displayPreview(code.text, maxCharacters: 80).text).tag(code.id) }
                    }.tint(Theme.accent).accessibilityIdentifier("normalizationTestCode")
                }
                if let code = review.testCode {
                    Text(LabTable.displayPreview(code.text, maxCharacters: 100).text).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    FHIRReaderLink("Read test code") { FHIRTextReader(title: "Supplied test code", text: code.text) }.accessibilityIdentifier("normalizationCodeReader")
                }
            } else if review.testMatch == .reviewedNames || review.testMatch == .reportedName {
                Text("Your match applies to this snapshot. No terminology equivalence was verified.").font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("normalizationNameScope")
            }
            if LabNormalization.conflictingCodes(first, second) { Text("The original test codes conflict. A name match cannot override them; this comparison stays literal.").foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("normalizationCodeConflict") }
            LabHistoryToggle(title: "I checked the test identity", value: $review.testChecked, identifier: "normalizationTestChecked")
        }
        .sheet(item: $editing) { field in
            let point = field == .first ? first : second
            let title = field == .target ? "Common UCUM code" : (field == .first ? (chronological ? "Earlier source UCUM code" : "First source UCUM code") : (chronological ? "Later source UCUM code" : "Second source UCUM code"))
            let text = field == .target ? review.targetCode : assignment(point)?.code ?? ""
            LabTextEditor(text: text, title: title, limit: 128, required: true, identifier: "normalizationCodeText", doneIdentifier: "finishNormalizationCode") { next in
                if field == .target {
                    review.targetCode = next
                    for i in review.units.indices { review.units[i].checked = false }
                } else if let i = review.units.firstIndex(where: { $0.pointID == point.id }) { review.units[i].code = next; review.units[i].checked = false }
            }
        }
    }
    private var matchTitle: String {
        switch review.testMatch {
        case .reportedName: return "Same reported name"
        case .originalCoding: return "Supplied test code"
        case .reviewedNames: return "My reviewed name match"
        case nil: return "Choose a match"
        }
    }
    private var matchPicker: some View {
        Picker("Test identity", selection: Binding(get: { review.testMatch }, set: setMatch)) {
            Text("Choose a match").tag(LabNormalizationReview.TestMatch?.none)
            if LabHistory.literalEqual(first.observation.test, second.observation.test) { Text("Same reported name").tag(LabNormalizationReview.TestMatch?.some(.reportedName)) }
            if !shared.isEmpty { Text("Supplied test code").tag(LabNormalizationReview.TestMatch?.some(.originalCoding)) }
            Text("My reviewed name match").tag(LabNormalizationReview.TestMatch?.some(.reviewedNames))
        }
    }
    @ViewBuilder private var testMatchControl: some View {
        if size.isAccessibilitySize {
            // Match the existing lab-import menu: its selected label measures
            // every line instead of using Picker's cropped collapsed row.
            Menu { matchPicker.pickerStyle(.inline) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(matchTitle).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).imageScale(.small).fixedSize().padding(.top, 4)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityLabel("Test identity").accessibilityValue(matchTitle).accessibilityIdentifier("normalizationTestMatch")
        } else {
            matchPicker.pickerStyle(.menu).labelsHidden().tint(Theme.accent).accessibilityIdentifier("normalizationTestMatch")
        }
    }
    private func assignment(_ point: LabHistory.Point) -> LabUnitAssignment? { review.units.first { $0.pointID == point.id } }
    @ViewBuilder private func unit(_ point: LabHistory.Point, label: String, field: CodeField) -> some View {
        if let assignment = assignment(point) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label).font(.headline)
                Text("Reported: " + point.observation.result + (point.observation.unit.isEmpty ? " · unit not recorded" : " " + point.observation.unit)).fixedSize(horizontal: false, vertical: true)
                Text("UCUM code").font(.subheadline).foregroundStyle(Theme.secondary)
                LabTextEditButton(text: assignment.code, title: "UCUM code", identifier: field == .first ? "normalizationFirst" : "normalizationSecond") { editing = field }
                if let basis = try? LabNormalization.assignmentBasis(point, code: assignment.code) {
                    Text(basis).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                } else { Text(assignmentIssue(point, code: assignment.code)).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
                LabHistoryToggle(title: "I checked this unit against the report", value: Binding(get: { self.assignment(point)?.checked ?? false }, set: { next in
                    if let i = review.units.firstIndex(where: { $0.pointID == point.id }) { review.units[i].checked = next }
                }), identifier: field == .first ? "normalizationFirstChecked" : "normalizationSecondChecked")
            }
        }
    }
    private func setMatch(_ match: LabNormalizationReview.TestMatch?) {
        review.testMatch = match; review.testCode = match == .originalCoding && shared.count == 1 ? shared[0] : nil; review.testChecked = false
    }
    private func unitIssue(_ code: String) -> String? {
        do { _ = try LabUnit.parse(code); return nil }
        catch let error as LabUnit.Failure { return error.message }
        catch { return "The unit code could not be read." }
    }
    private func assignmentIssue(_ point: LabHistory.Point, code: String) -> String {
        do { return try LabNormalization.assignmentBasis(point, code: code) }
        catch let error as LabNormalization.ReviewFailure { return error.message }
        catch let error as LabUnit.Failure { return error.message }
        catch { return "The unit assignment could not be checked." }
    }
    private static let supportedText = """
    Reviewed linear UCUM conversions

    Codes are case-sensitive ASCII. A printed µ or μ can be explicitly mapped to u. Printed labels, original codes and your assignments remain separate.

    Supported families
    SI base and common derived units; g, mol, L/l and their metric prefixes; s, min, h, d, wk; %, parts-per units; kat and U; concentration and count-density terms. U means catalytic activity, not an international/arbitrary unit. Matching units do not establish matching assays.

    Syntax
    Products use a dot. Division and products apply left-to-right with equal precedence. Parentheses group terms. Integer powers follow simple units. Positive integer factors and 10*/10^ scales are supported. A power cannot follow a parenthesized term.

    Limits
    Maximum 128 ASCII bytes
    Maximum 64 components
    Maximum 8 nested groups
    Simple powers from −24 to 24
    Dimension powers from −64 to 64
    Prime-factor powers from −1,024 to 1,024
    Positive integer factors at most 1,000,000,000

    Unknown atoms reject the complete term.

    Kept as wording
    Nonlinear, arbitrary, international and annotated units; mass-to-mole or mole-to-count conversions; unknown code definitions; nonterminating or unrepresentable exact decimals. No remote terminology service, inferred molecular mass or rounded fallback is used.

    Scope
    This is a supported linear subset, not full UCUM conformance. Reference wording and flags stay in their original units. Neither unit compatibility nor a reviewed name match establishes clinical comparability.
    """
}

struct LabConvertedValuesView: View {
    let comparison: LabHistory.Comparison
    var body: some View {
        if let normalized = comparison.normalization, !normalized.converted.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Converted values").font(.headline)
                ForEach(normalized.converted, id: \.pointID) { value in
                    let isFirst = value.pointID == comparison.first.id
                    let point = isFirst ? comparison.first : comparison.second
                    VStack(alignment: .leading, spacing: 8) {
                        Text(comparison.chronological ? (isFirst ? "Earlier result" : "Later result") : (isFirst ? "First result" : "Second result")).font(.subheadline).foregroundStyle(Theme.secondary)
                        Text("Reported: " + point.observation.result + " " + point.observation.unit).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(isFirst ? "normalizedReported-0" : "normalizedReported-1")
                        Text("Converted").font(.subheadline).foregroundStyle(Theme.secondary)
                        Text(value.value).font(.title2.bold().monospacedDigit()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(isFirst ? "normalizedValue-0" : "normalizedValue-1")
                        Text("Common unit: " + normalized.unit).fixedSize(horizontal: false, vertical: true)
                        Text("Exact factor: " + value.factor + " · from " + value.sourceCode).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(value.basis).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
