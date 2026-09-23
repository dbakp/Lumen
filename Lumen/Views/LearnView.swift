import SwiftUI

// MARK: - Learn: short, practical reads about sleep and energy

public struct LearnView: View {
    @State private var query = ""
    public init() {}

    var filtered: [Article] {
        query.isEmpty ? Article.all : Article.all.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query) }
    }

    public var body: some View {
        ScrollView {
            RowGroup {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                    NavigationLink { ArticleView(article: a) } label: {
                        LumenRow(a.title, subtitle: "\(a.tag) · \(a.minutes) min read")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.food)
        .navigationTitle("Learn")
        .searchable(text: $query, prompt: "Search")
    }
}

struct ArticleView: View {
    let article: Article
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(article.tag) · \(article.minutes) min read").font(.subheadline).foregroundStyle(Theme.secondary)
                Text(article.title).font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text)
                Text(article.body).font(.body).foregroundStyle(Theme.text.opacity(0.88)).lineSpacing(7).padding(.top, 6)
            }
            .padding(Theme.gutter)
        }
        .lumenScreen(Theme.food)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Article: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
}
