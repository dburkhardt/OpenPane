import AppKit
import OpenPaneCore
import SwiftUI
import UniformTypeIdentifiers

enum BinaryInspectorMode: String, CaseIterable, Identifiable {
    case rawText = "Raw Text"
    case hex = "Hex"

    var id: Self { self }
}

enum BinaryDisplayEncoding: String, CaseIterable, Identifiable {
    case utf8 = "UTF-8"
    case utf16LittleEndian = "UTF-16 LE"
    case utf16BigEndian = "UTF-16 BE"
    case windows1252 = "Windows-1252"
    case isoLatin1 = "ISO Latin 1"
    case macRoman = "Mac Roman"

    var id: Self { self }

    fileprivate var coreEncoding: TextEncoding {
        switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .windows1252: .windows1252
        case .isoLatin1: .isoLatin1
        case .macRoman: .macOSRoman
        }
    }
}

struct BinaryInspectorView: View {
    let data: Data
    let sourceURL: URL?
    var totalByteCount: Int?

    @State private var mode = BinaryInspectorMode.rawText
    @State private var encoding = BinaryDisplayEncoding.utf8
    @State private var saveError: String?

    private var decodedText: String {
        BinaryInspectorFormatter.decodedText(data, encoding: encoding)
    }

    private var isTruncated: Bool {
        guard let totalByteCount else { return false }
        return totalByteCount > data.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("View", selection: $mode) {
                    ForEach(BinaryInspectorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                if mode == .rawText {
                    Picker("Encoding", selection: $encoding) {
                        ForEach(BinaryDisplayEncoding.allCases) { encoding in
                            Text(encoding.rawValue).tag(encoding)
                        }
                    }
                    .frame(width: 170)
                }

                Spacer()

                Text(ByteCountFormatter.string(
                    fromByteCount: Int64(totalByteCount ?? data.count),
                    countStyle: .file
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    saveTextCopy()
                } label: {
                    Label("Save Text Copy As…", systemImage: "square.and.arrow.down")
                }
                .disabled(isTruncated)
                .help(
                    isTruncated
                        ? "A text copy is unavailable because only a bounded prefix was loaded."
                        : "Save the decoded text as a separate UTF-8 file."
                )
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(.bar)

            if isTruncated {
                Label(
                    "Showing the first \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) of this file. Saving a partial text copy is disabled.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .background(Color.orange.opacity(0.09))
            }

            Divider()

            switch mode {
            case .rawText:
                ScrollView([.horizontal, .vertical]) {
                    Text(decodedText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .accessibilityLabel("Decoded binary text")

            case .hex:
                HexDumpView(data: data)
            }
        }
        .alert(
            "Couldn’t Save Text Copy",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func saveTextCopy() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue =
            (sourceURL?.deletingPathExtension().lastPathComponent ?? "Binary Text") + ".txt"

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if let sourceURL,
           destination.standardizedFileURL.resolvingSymlinksInPath()
            == sourceURL.standardizedFileURL.resolvingSymlinksInPath() {
            saveError = "Choose a different file. OpenPane never overwrites a binary source."
            return
        }

        do {
            try decodedText.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct HexDumpView: View {
    let data: Data

    private var rows: [HexRow] {
        HexRenderer.rows(for: data)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    Text("00000000")
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    ForEach(rows) { row in
                        let formatted = BinaryInspectorFormatter.hexRow(row)
                        Text(formatted)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityLabel("Offset \(row.offset), \(formatted)")
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityLabel("Hexadecimal file inspector")
    }
}

enum BinaryInspectorFormatter {
    static func decodedText(
        _ data: Data,
        encoding: BinaryDisplayEncoding
    ) -> String {
        BinaryTextRenderer.render(data, encoding: encoding.coreEncoding)
    }

    static func hexRow(_ row: HexRow) -> String {
        var values = row.bytes.map { String(format: "%02X", $0) }
        values.append(contentsOf: repeatElement("  ", count: max(0, 16 - values.count)))
        let left = values.prefix(8).joined(separator: " ")
        let right = values.dropFirst(8).joined(separator: " ")
        return "\(row.formattedOffset)  \(left)  \(right)  |\(row.ascii)|"
    }
}
