import SwiftUI

struct OpenSourceLicensesView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "ZIPFoundation-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License could not be loaded." }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ZIPFoundation").font(.title.bold())
                Text("Version 0.9.20 · MIT license").font(.subheadline).foregroundStyle(Theme.secondary)
                Text("Reads Apple Health ZIP exports on your device.").font(.body)
                Text(license).font(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled).accessibilityIdentifier("zipLicenseText")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Open-source licenses").navigationBarTitleDisplayMode(.inline)
    }
}
