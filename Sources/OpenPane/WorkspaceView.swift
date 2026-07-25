import AppKit
import SwiftUI

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case preview = "Preview"
    case split = "Split"
    case source = "Source"

    var id: Self { self }
}

struct WorkspaceView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @AppStorage("workspaceMode") private var storedMode = WorkspaceMode.preview.rawValue
    @State private var showOutline = true
    @State private var showProofreader = false
    @State private var selectedHeading: String?
    @State private var exportError: String?

    private var mode: Binding<WorkspaceMode> {
        Binding(
            get: { WorkspaceMode(rawValue: storedMode) ?? .preview },
            set: { storedMode = $0.rawValue }
        )
    }

    private var model: MarkdownModel {
        MarkdownModel(source: document.text)
    }

    var body: some View {
        NavigationSplitView {
            if showOutline {
                OutlineView(model: model, selection: $selectedHeading)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 320)
            }
        } detail: {
            Group {
                switch mode.wrappedValue {
                case .preview:
                    MarkdownPreview(model: model, selectedHeading: $selectedHeading)
                case .source:
                    sourceEditor
                case .split:
                    HSplitView {
                        sourceEditor
                        MarkdownPreview(model: model, selectedHeading: $selectedHeading)
                    }
                }
            }
            .inspector(isPresented: $showProofreader) {
                ProofreaderView(source: document.text)
                    .inspectorColumnWidth(min: 260, ideal: 310, max: 420)
            }
        }
        .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showOutline.toggle()
                } label: {
                    Label("Outline", systemImage: "sidebar.left")
                }

                Picker("View", selection: mode) {
                    ForEach(WorkspaceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)

                Button {
                    showProofreader.toggle()
                } label: {
                    Label("Proofreader", systemImage: "checkmark.bubble")
                }

                Button {
                    exportHTML()
                } label: {
                    Label("Export HTML", systemImage: "square.and.arrow.up")
                }
            }
        }
        .alert(
            "Couldn’t Export",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    private var sourceEditor: some View {
        TextEditor(text: $document.text)
            .font(.system(.body, design: .monospaced))
            .lineSpacing(3)
            .padding(12)
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
    }

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue =
            (fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled") + ".html"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try HTMLExporter.export(
                model: model,
                title: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled",
                to: url
            )
        } catch {
            exportError = error.localizedDescription
        }
    }
}
