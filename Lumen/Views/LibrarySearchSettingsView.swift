import SwiftUI

struct LibrarySearchSettingsView: View {
    @ObservedObject private var search = SemanticSearchService.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Form {
            Section {
                #if DEBUG && targetEnvironment(simulator)
                if SemanticSearchService.usesFixture {
                    Text("Local model fixture · no network download").font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("meaningSearchFixtureLabel")
                }
                #endif
                Text("Find related wording").font(.title2.bold()).fontWidth(.expanded)
                Text("Add English topic matches to keyword search in records you share with the Assistant.")
                Text("A topic match may not answer your question. Check the saved excerpt.").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Section {
                if search.installed {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Related-topic search")
                            enabledToggle.labelsHidden().accessibilityLabel("Related-topic search").frame(minHeight: 44)
                        }
                    } else { enabledToggle }
                    Text(search.enabled ? "On for new questions in English." : "Off. Model files stay on this iPhone.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else if !search.busy {
                    LabeledContent("Model download", value: "45 MB")
                    Button { search.downloadAndEnable() } label: { Label(downloadLabel, systemImage: "arrow.down.circle") }
                        .foregroundStyle(Theme.accent).accessibilityIdentifier("meaningSearchDownload")
                }
                if search.busy {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(phaseLabel).font(.headline).accessibilityIdentifier("meaningSearchStatus")
                        if search.phase == .downloading {
                            ProgressView(value: search.fraction).accessibilityLabel("Model transfer")
                            Text("\(ByteCountFormatter.string(fromByteCount: search.receivedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: SemanticModelPackage.downloadBytes, countStyle: .file))")
                                .font(.subheadline.monospacedDigit()).accessibilityIdentifier("meaningSearchBytes")
                        } else { ProgressView().accessibilityLabel(phaseLabel) }
                        if [.cleaning, .downloading, .checking, .preparing].contains(search.phase) {
                            Button("Cancel") { search.cancelDownload() }.foregroundStyle(Theme.accent).accessibilityIdentifier("meaningSearchCancel")
                        }
                    }.padding(.vertical, 6)
                }
                if let problem = search.problem { Text(problem).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityIdentifier("meaningSearchError") }
                if search.installed || search.problem != nil {
                    Button(role: .destructive) { search.removeModel() } label: { Label("Delete model", systemImage: "trash") }
                        .foregroundStyle(Theme.destructive).disabled(search.busy).accessibilityIdentifier("meaningSearchDelete")
                }
            } header: { Text("On this iPhone") } footer: {
                Text("Keyword search stays available. Preparing needs at least 250 MB of free space; the downloaded copy is removed after preparation. Model files are excluded from Lumen backups.")
            }
            Section {
                Text("Only shared Library text is searched. Topic matching runs on this iPhone; record text isn't sent to the model download host.")
                Text("Selected excerpts may still go to your chosen AI provider with your question. Review AI settings and each record's sharing choice.")
            } header: { Text("Sharing") }
            Section {
                LabeledContent("Language", value: "English")
                Text("Other questions use keyword search. Topic search can miss relevant records or select an unrelated one.").font(.subheadline).foregroundStyle(Theme.secondary)
                NavigationLink("Model & license") { MiniLMLicenseView() }
            } header: { Text("Model details") }
        }.scrollContentBackground(.hidden).lumenScreen().tint(Theme.accent)
            .navigationTitle("Library search").navigationBarTitleDisplayMode(.inline)
    }
    private var enabledToggle: some View {
        Toggle("Related-topic search", isOn: Binding(get: { search.enabled }, set: { search.setEnabled($0) }))
            .disabled(search.busy).accessibilityIdentifier("meaningSearchToggle")
    }
    private var downloadLabel: String {
        #if DEBUG && targetEnvironment(simulator)
        if SemanticSearchService.usesFixture { return "Install local test model" }
        #endif
        return "Download & enable"
    }
    private var phaseLabel: String {
        switch search.phase {
        case .idle: return ""
        case .cleaning: return "Clearing old model cache"
        case .downloading:
            #if DEBUG && targetEnvironment(simulator)
            if SemanticSearchService.usesFixture { return "Copying local model" }
            #endif
            return "Downloading model"
        case .checking: return "Checking model"
        case .preparing: return "Preparing model"
        case .stopping: return "Stopping model work"
        case .removing: return "Removing model"
        }
    }
}

struct MiniLMLicenseView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "MiniLM-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "License could not be loaded." }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MiniLM Library search").font(.title.bold()).fontWidth(.expanded)
                Text("all-MiniLM-L6-v2 · Apache 2.0").font(.subheadline).foregroundStyle(Theme.secondary)
                Text("General English text retrieval. Clinical accuracy has not been established.")
                Link("Original model", destination: URL(string: "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2")!)
                Link("Core ML conversion by haihengh", destination: URL(string: "https://huggingface.co/haihengh/all-MiniLM-L6-v2-coreml/tree/" + SemanticModelPackage.revision)!)
                Text("Pinned revision: " + SemanticModelPackage.revision).font(.footnote).textSelection(.enabled)
                Text(license).font(.footnote).foregroundStyle(Theme.secondary).textSelection(.enabled).accessibilityIdentifier("miniLMLicenseText")
            }.frame(maxWidth: .infinity, alignment: .leading).padding(Theme.gutter)
        }.lumenScreen().navigationTitle("Model & license").navigationBarTitleDisplayMode(.inline)
    }
}
