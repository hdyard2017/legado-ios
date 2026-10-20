import SwiftUI

struct RSSAddBookView: View {
    @EnvironmentObject private var books: BookLibraryModel
    @EnvironmentObject private var sources: SourceLibraryModel
    let bookURL: String
    @State private var resolved: AddBookURLResult?
    @State private var existing: (Book, BookSource)?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let existing {
                BookDetailView(book: existing.0, source: existing.1)
            } else if let resolved {
                BookDetailView(book: resolved.book, source: resolved.source)
            } else if let errorMessage {
                ReadingUnavailableView("无法添加书籍", systemImage: "books.vertical.circle", description: Text(errorMessage))
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在匹配书源并解析详情…").foregroundColor(.secondary)
                    Text(bookURL).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary).lineLimit(3)
                }.padding()
            }
        }
        .navigationTitle("添加到书架")
        .task(id: bookURL) { await load() }
    }

    private func load() async {
        if let book = books.books.first(where: { $0.bookUrl == bookURL }),
           let source = sources.sources.first(where: { $0.bookSourceUrl == book.origin }) {
            existing = (book, source)
            return
        }
        do {
            resolved = try await AddBookURLService().resolve(bookURL: bookURL, sources: sources.sources)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
