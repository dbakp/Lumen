import SwiftUI

/// Preserve the user's in-progress decimal text, including trailing zeros.
/// Numeric-format bindings can rewrite a field while its keyboard is still typing.
struct HealthAmountField: View {
    let placeholder: String
    @Binding private var value: Double?
    @State private var text: String
    init(_ placeholder: String, value: Binding<Double?>) {
        self.placeholder = placeholder; _value = value
        _text = State(initialValue: value.wrappedValue.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...8))) } ?? "")
    }
    var body: some View {
        TextField(placeholder, text: $text)
            .onChange(of: text) { _, text in
                value = HealthLogDrafting.amount(text)
            }
    }
}
