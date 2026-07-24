import SwiftUI

struct OutlineView: View {
    let model: MarkdownModel
    @Binding var selection: UUID?

    var body: some View {
        List(model.headings, selection: $selection) { heading in
            Text(heading.title)
                .lineLimit(2)
                .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                .tag(heading.id)
        }
        .navigationTitle("Outline")
        .overlay {
            if model.headings.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Add Markdown headings to build an outline.")
                )
            }
        }
    }
}
