import SwiftUI

/// Keep values readable at full Dynamic Type instead of competing for two
/// narrow columns. Ordinary text sizes retain the native grouped-form row.
struct SettingsValueRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let value: String

    init(_ title: String, value: String) { self.title = title; self.value = value }

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).fixedSize(horizontal: false, vertical: true)
                    Text(value).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent(title, value: value)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsStepper: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let value: String
    let selection: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let identifier: String

    init(_ title: String, value: String, selection: Binding<Double>, in range: ClosedRange<Double>, step: Double, identifier: String) {
        self.title = title; self.value = value; self.selection = selection
        self.range = range; self.step = step; self.identifier = identifier
    }

    var body: some View {
        if textSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                // The native stepper carries the same accessible label/value.
                SettingsValueRow(title, value: value).accessibilityHidden(true)
                control.labelsHidden().frame(minHeight: 44)
            }
            .padding(.vertical, 4)
        } else {
            control
        }
    }

    private var control: some View {
        Stepper(value: selection, in: range, step: step) { LabeledContent(title, value: value) }
            .accessibilityIdentifier(identifier)
    }
}

/// Reuse the reviewed Library menu pattern when Picker's collapsed selected
/// label would truncate wording at accessibility sizes.
struct SettingsPicker<Selection: Hashable, Options: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let value: String
    let selection: Binding<Selection>
    let identifier: String
    let options: Options

    init(_ title: String, value: String, selection: Binding<Selection>, identifier: String, @ViewBuilder options: () -> Options) {
        self.title = title; self.value = value; self.selection = selection
        self.identifier = identifier; self.options = options()
    }

    private var picker: some View { Picker(title, selection: selection) { options } }

    var body: some View {
        if textSize.isAccessibilitySize {
            Menu { picker.pickerStyle(.inline) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
                    HStack(alignment: .top, spacing: 12) {
                        Text(value).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.caption).imageScale(.small).fixedSize().padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    .foregroundStyle(Theme.accent)
                }
                // Match the native button's accessible frame: title, value and
                // the space between them all activate the same menu.
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityValue(value).accessibilityIdentifier(identifier)
        } else {
            picker.accessibilityIdentifier(identifier)
        }
    }
}
