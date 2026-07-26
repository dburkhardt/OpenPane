import SwiftUI

struct QuickOpenView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selection: URL?
    @FocusState private var searchFocused: Bool

    private var results: [URL] {
        QuickOpenMatcher.matches(
            query: query,
            files: store.quickOpenFiles,
            relativePath: store.relativePath(for:)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Open a file by name or path",
                    text: $query
                )
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    openSelection()
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }

                if store.isIndexingQuickOpen {
                    ProgressView()
                        .controlSize(.small)
                        .help("Indexing file names")
                }
            }
            .font(.title3)
            .padding(14)

            Divider()

            if results.isEmpty {
                ContentUnavailableView {
                    Label(
                        query.isEmpty ? "No Files" : "No Matches",
                        systemImage: "doc.text.magnifyingglass"
                    )
                } description: {
                    if store.isIndexingQuickOpen {
                        Text("OpenPane is indexing file names.")
                    } else if query.isEmpty {
                        Text("This workspace has no visible files.")
                    } else {
                        Text("Try part of a file name or relative path.")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results, id: \.self, selection: $selection) { url in
                    QuickOpenRow(
                        url: url,
                        relativePath: store.relativePath(for: url)
                    )
                    .tag(url)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        store.open(url, behavior: .pinned)
                        isPresented = false
                    }
                }
                .listStyle(.plain)
                .onChange(of: results) { _, newResults in
                    if let selection, newResults.contains(selection) {
                        return
                    }
                    selection = newResults.first
                }
            }

            Divider()
            HStack {
                Text("↑↓ Navigate")
                Text("↩ Open")
                Spacer()
                Text("\(results.count) result\(results.count == 1 ? "" : "s")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 620, height: 430)
        .onAppear {
            selection = results.first
            searchFocused = true
            if store.quickOpenFiles.isEmpty {
                store.rebuildQuickOpenIndex()
            }
        }
        .onExitCommand {
            isPresented = false
        }
    }

    private func openSelection() {
        guard let target = selection ?? results.first else { return }
        store.open(target, behavior: .preview)
        isPresented = false
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            selection = nil
            return
        }
        let currentIndex = selection.flatMap {
            results.firstIndex(of: $0)
        } ?? 0
        let nextIndex = min(
            max(0, currentIndex + offset),
            results.count - 1
        )
        selection = results[nextIndex]
    }
}

private struct QuickOpenRow: View {
    let url: URL
    let relativePath: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .lineLimit(1)
                Text(relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

enum QuickOpenMatcher {
    static func matches(
        query: String,
        files: [URL],
        relativePath: (URL) -> String,
        limit: Int = 200
    ) -> [URL] {
        let tokens = query
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).foldedForWorkspaceSearch }

        if tokens.isEmpty {
            return Array(files.prefix(limit))
        }

        return files.compactMap { url -> (URL, Int, String)? in
            let name = url.lastPathComponent.foldedForWorkspaceSearch
            let path = relativePath(url).foldedForWorkspaceSearch
            guard tokens.allSatisfy({ path.contains($0) }) else { return nil }

            var score = 0
            for token in tokens {
                if name == token {
                    score += 1_000
                } else if name.hasPrefix(token) {
                    score += 500
                } else if name.contains(token) {
                    score += 250
                } else {
                    score += 50
                }
            }
            score -= path.count / 20
            return (url, score, path)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 {
                return lhs.1 > rhs.1
            }
            return lhs.2.localizedStandardCompare(rhs.2) == .orderedAscending
        }
        .prefix(limit)
        .map(\.0)
    }
}

private extension String {
    var foldedForWorkspaceSearch: String {
        folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
    }
}
