import AppKit
import PDFKit
import SwiftUI

private enum PDFReaderAction: Equatable {
    case none
    case previousPage
    case nextPage
    case zoomIn
    case zoomOut
    case actualSize
    case fit
    case rotateLeft
    case rotateRight
    case printDocument
    case goToPage(Int)
    case selectSearchResult(Int)
}

private struct PDFReaderCommand: Equatable {
    var revision = 0
    var action = PDFReaderAction.none
}

struct PDFReaderView: View {
    let url: URL
    let isActive: Bool

    @State private var document: PDFDocument?
    @State private var loadError: String?
    @State private var command = PDFReaderCommand()
    @State private var showsThumbnails = true
    @State private var currentPage = 0
    @State private var searchText = ""
    @State private var searchResults: [PDFSelection] = []
    @State private var selectedSearchResult = 0
    @FocusState private var isSearchFocused: Bool

    init(url: URL, isActive: Bool = false) {
        self.url = url
        self.isActive = isActive
        let loadedDocument = PDFDocument(url: url)
        PDFReadOnlyPolicy.apply(to: loadedDocument)
        _document = State(initialValue: loadedDocument)
    }

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 0) {
                    toolbar(document: document)
                    Divider()
                    PDFReaderCanvas(
                        document: document,
                        showsThumbnails: showsThumbnails,
                        searchResults: searchResults,
                        command: command,
                        onPageChanged: { currentPage = $0 }
                    )
                }
            } else {
                ContentUnavailableView(
                    "PDF Couldn’t Be Opened",
                    systemImage: "doc.richtext",
                    description: Text(loadError ?? "The document may be damaged or encrypted.")
                )
            }
        }
        .task(id: url) {
            guard document == nil else { return }
            document = PDFDocument(url: url)
            PDFReadOnlyPolicy.apply(to: document)
            if document == nil {
                loadError = "OpenPane could not read \(url.lastPathComponent)."
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openPaneFind)
        ) { _ in
            guard isActive else { return }
            isSearchFocused = true
        }
        .accessibilityLabel("PDF reader")
    }

    private func toolbar(document: PDFDocument) -> some View {
        HStack(spacing: 8) {
            Button {
                showsThumbnails.toggle()
            } label: {
                Label("Thumbnails", systemImage: "sidebar.left")
            }

            Divider().frame(height: 18)

            Button {
                send(.previousPage)
            } label: {
                Label("Previous Page", systemImage: "chevron.up")
            }
            .disabled(currentPage <= 0)

            TextField(
                "Page",
                value: Binding(
                    get: { currentPage + 1 },
                    set: { send(.goToPage(max(0, $0 - 1))) }
                ),
                format: .number
            )
            .multilineTextAlignment(.trailing)
            .frame(width: 44)
            .accessibilityLabel("Page number")

            Text("of \(document.pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                send(.nextPage)
            } label: {
                Label("Next Page", systemImage: "chevron.down")
            }
            .disabled(currentPage + 1 >= document.pageCount)

            Divider().frame(height: 18)

            Button { send(.zoomOut) } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            Button { send(.zoomIn) } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            Button { send(.fit) } label: {
                Label("Zoom to Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Spacer()

            HStack(spacing: 4) {
                TextField("Find in PDF", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 280)
                    .onSubmit { performSearch(in: document) }
                    .onChange(of: searchText) { _, _ in
                        performSearch(in: document)
                    }

                if !searchResults.isEmpty {
                    Text("\(selectedSearchResult + 1)/\(searchResults.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        selectSearchResult(selectedSearchResult - 1)
                    } label: {
                        Label("Previous Result", systemImage: "chevron.up")
                    }
                    Button {
                        selectSearchResult(selectedSearchResult + 1)
                    } label: {
                        Label("Next Result", systemImage: "chevron.down")
                    }
                }
            }

            Menu {
                Button("Actual Size") { send(.actualSize) }
                Button("Zoom to Fit") { send(.fit) }
                Divider()
                Button("Rotate Left") { send(.rotateLeft) }
                Button("Rotate Right") { send(.rotateRight) }
                Divider()
                Button("Print…") { send(.printDocument) }
                    .keyboardShortcut("p", modifiers: .command)
            } label: {
                Label("PDF Actions", systemImage: "ellipsis.circle")
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(.bar)
    }

    private func send(_ action: PDFReaderAction) {
        command.revision &+= 1
        command.action = action
    }

    private func performSearch(in document: PDFDocument) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            selectedSearchResult = 0
            send(.selectSearchResult(-1))
            return
        }

        searchResults = document.findString(query, withOptions: [.caseInsensitive])
        selectedSearchResult = 0
        if !searchResults.isEmpty {
            send(.selectSearchResult(0))
        }
    }

    private func selectSearchResult(_ index: Int) {
        guard !searchResults.isEmpty else { return }
        selectedSearchResult =
            (index % searchResults.count + searchResults.count) % searchResults.count
        send(.selectSearchResult(selectedSearchResult))
    }
}

private struct PDFReaderCanvas: NSViewRepresentable {
    let document: PDFDocument
    let showsThumbnails: Bool
    let searchResults: [PDFSelection]
    let command: PDFReaderCommand
    let onPageChanged: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChanged: onPageChanged)
    }

    func makeNSView(context: Context) -> PDFReaderContainer {
        let container = PDFReaderContainer()
        PDFReadOnlyPolicy.apply(to: document)
        container.pdfView.document = document
        container.setThumbnailsVisible(showsThumbnails)
        context.coordinator.observe(container.pdfView)
        return container
    }

    func updateNSView(_ container: PDFReaderContainer, context: Context) {
        context.coordinator.onPageChanged = onPageChanged
        if container.pdfView.document !== document {
            PDFReadOnlyPolicy.apply(to: document)
            container.pdfView.document = document
        }
        container.setThumbnailsVisible(showsThumbnails)
        container.pdfView.highlightedSelections = searchResults

        guard context.coordinator.lastCommandRevision != command.revision else { return }
        context.coordinator.lastCommandRevision = command.revision
        perform(command.action, in: container.pdfView)
    }

    private func perform(_ action: PDFReaderAction, in pdfView: PDFView) {
        switch action {
        case .none:
            break
        case .previousPage:
            pdfView.goToPreviousPage(nil)
        case .nextPage:
            pdfView.goToNextPage(nil)
        case .zoomIn:
            pdfView.zoomIn(nil)
        case .zoomOut:
            pdfView.zoomOut(nil)
        case .actualSize:
            pdfView.autoScales = false
            pdfView.scaleFactor = 1
        case .fit:
            pdfView.autoScales = true
        case .rotateLeft:
            guard let page = pdfView.currentPage else { return }
            page.rotation = (page.rotation + 270) % 360
        case .rotateRight:
            guard let page = pdfView.currentPage else { return }
            page.rotation = (page.rotation + 90) % 360
        case .printDocument:
            pdfView.print(
                with: NSPrintInfo.shared,
                autoRotate: true,
                pageScaling: .pageScaleToFit
            )
        case .goToPage(let index):
            guard let document = pdfView.document,
                  document.pageCount > 0,
                  let page = document.page(at: min(max(0, index), document.pageCount - 1)) else {
                return
            }
            pdfView.go(to: page)
        case .selectSearchResult(let index):
            guard index >= 0,
                  let selections = pdfView.highlightedSelections,
                  selections.indices.contains(index) else {
                pdfView.currentSelection = nil
                return
            }
            let selection = selections[index]
            pdfView.currentSelection = selection
            pdfView.go(to: selection)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var lastCommandRevision = 0
        var onPageChanged: (Int) -> Void

        init(onPageChanged: @escaping (Int) -> Void) {
            self.onPageChanged = onPageChanged
            super.init()
        }

        func observe(_ pdfView: PDFView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageDidChange(_:)),
                name: .PDFViewPageChanged,
                object: pdfView,
            )
        }

        @objc
        private func pageDidChange(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage else {
                return
            }
            onPageChanged(document.index(for: page))
        }
    }
}

enum PDFReadOnlyPolicy {
    static func apply(to document: PDFDocument?) {
        guard let document else { return }
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                annotation.isReadOnly = true
                if let action = annotation.action,
                   !(action is PDFActionGoTo),
                   !(action is PDFActionURL),
                   !(action is PDFActionNamed) {
                    annotation.action = nil
                }
            }
        }
    }
}

@MainActor
private final class PDFReaderContainer: NSView {
    let pdfView = PDFView()
    private let thumbnailView = PDFThumbnailView()
    private let thumbnailScrollView = NSScrollView()
    private let divider = NSBox()
    private var thumbnailsVisible = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.backgroundColor = .windowBackgroundColor

        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 104, height: 138)
        thumbnailView.allowsDragging = false
        thumbnailScrollView.documentView = thumbnailView
        thumbnailScrollView.hasVerticalScroller = true
        thumbnailScrollView.autohidesScrollers = true
        thumbnailScrollView.drawsBackground = false

        divider.boxType = .separator
        addSubview(thumbnailScrollView)
        addSubview(divider)
        addSubview(pdfView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setThumbnailsVisible(_ visible: Bool) {
        guard thumbnailsVisible != visible else { return }
        thumbnailsVisible = visible
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let thumbnailWidth: CGFloat = thumbnailsVisible ? min(170, bounds.width * 0.28) : 0
        thumbnailScrollView.isHidden = !thumbnailsVisible
        divider.isHidden = !thumbnailsVisible
        thumbnailScrollView.frame = NSRect(
            x: 0,
            y: 0,
            width: thumbnailWidth,
            height: bounds.height
        )
        divider.frame = NSRect(
            x: thumbnailWidth,
            y: 0,
            width: thumbnailsVisible ? 1 : 0,
            height: bounds.height
        )
        pdfView.frame = NSRect(
            x: thumbnailWidth + (thumbnailsVisible ? 1 : 0),
            y: 0,
            width: max(0, bounds.width - thumbnailWidth - (thumbnailsVisible ? 1 : 0)),
            height: bounds.height
        )
    }
}
