import SwiftUI

// MARK: - Learn library (sleep knowledge, Rise parity)

public struct LearnView: View {
    @State private var query = ""
    @State private var selected: Article?

    public init() {}

    var filtered: [Article] {
        if query.isEmpty { return Article.all }
        return Article.all.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(filtered) { a in
                    Button { selected = a; haptic(.light) } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(a.tag.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.cyan).tracking(0.8)
                                    Text(a.title).font(.headline).foregroundStyle(.white).multilineTextAlignment(.leading)
                                    Text("\(a.minutes) min read").font(.caption).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 90)
        }
        .background(AuroraBackground())
        .navigationTitle("Learn")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Sleep debt, caffeine, naps…")
        .sheet(item: $selected) { a in ArticleView(article: a) }
    }
}

struct ArticleView: View {
    let article: Article
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.tag.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.cyan).tracking(1)
                        Text(article.title).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                        Text("\(article.minutes) min read").font(.caption).foregroundStyle(.white.opacity(0.6))
                        Divider().background(.white.opacity(0.15))
                        Text(article.body).font(.body).foregroundStyle(.white.opacity(0.9)).lineSpacing(6)
                    }
                    .padding(22)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

extension Article: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
}
