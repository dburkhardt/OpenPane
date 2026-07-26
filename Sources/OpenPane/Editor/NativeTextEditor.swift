import AppKit
import OpenPaneCore
import SwiftUI

struct TextEditorPosition: Equatable, Sendable {
    var line = 1
    var column = 1
    var selectionLength = 0
}

struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String

    var languageID: String
    var isEditable: Bool
    var wordWrap: Bool
    var fontSize: CGFloat
    var showsLineNumbers = true
    var showsWhitespace = false
    var findRequest = 0
    var commentRequest = 0
    var goToLineRequest = 0
    var goToLineNumber = 1
    var initialEditorState = TextEditorState()
    var onPositionChange: (TextEditorPosition) -> Void = { _ in }
    var onEditorStateChange: (TextEditorState) -> Void = { _ in }
    var onSave: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EditorContainerView {
        let container = EditorContainerView()
        let textView = container.textView
        textView.delegate = context.coordinator

        context.coordinator.container = container
        context.coordinator.highlighter.setLanguage(languageID)
        context.coordinator.isApplyingProgrammaticChange = true
        textView.string = text
        context.coordinator.isApplyingProgrammaticChange = false
        context.coordinator.applyPresentation(to: textView)
        context.coordinator.refreshHighlights()
        container.lineNumberView.needsDisplay = true
        container.onScroll = { [weak coordinator = context.coordinator] in
            coordinator?.reportEditorState()
        }
        Task { @MainActor [weak container, weak coordinator = context.coordinator] in
            await Task.yield()
            guard let container, let coordinator else { return }
            coordinator.restoreEditorStateIfNeeded(in: container)
        }
        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        context.coordinator.parent = self
        let textView = container.textView

        if textView.string != text, !context.coordinator.isApplyingUserChange {
            context.coordinator.isApplyingProgrammaticChange = true
            let selections = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selections.compactMap { value in
                let range = value.rangeValue
                guard range.location <= text.utf16.count else { return nil }
                return NSValue(
                    range: NSRange(
                        location: range.location,
                        length: min(range.length, text.utf16.count - range.location)
                    )
                )
            }
            context.coordinator.isApplyingProgrammaticChange = false
        }

        if context.coordinator.languageID != languageID {
            context.coordinator.languageID = languageID
            context.coordinator.highlighter.setLanguage(languageID)
            context.coordinator.refreshHighlights()
        }

        context.coordinator.applyPresentation(to: textView)
        container.showsLineNumbers = showsLineNumbers
        container.showsWhitespace = showsWhitespace
        container.lineNumberView.needsDisplay = true
        container.whitespaceOverlayView.needsDisplay = true

        if context.coordinator.lastFindRequest != findRequest {
            context.coordinator.lastFindRequest = findRequest
            textView.performFindPanelAction(
                NSNumber(value: NSFindPanelAction.showFindPanel.rawValue)
            )
        }

        if context.coordinator.lastCommentRequest != commentRequest {
            context.coordinator.lastCommentRequest = commentRequest
            context.coordinator.toggleLineComments()
        }

        if context.coordinator.lastGoToLineRequest != goToLineRequest {
            context.coordinator.lastGoToLineRequest = goToLineRequest
            context.coordinator.goToLine(goToLineNumber)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        weak var container: EditorContainerView?
        let highlighter = IncrementalSyntaxHighlighter()
        var languageID: String
        var isApplyingProgrammaticChange = false
        var isApplyingUserChange = false
        var pendingEdit: IncrementalSyntaxHighlighter.Edit?
        var lastFindRequest = 0
        var lastCommentRequest = 0
        var lastGoToLineRequest = 0
        var didRestoreEditorState = false
        var lastReportedEditorState: TextEditorState?

        init(_ parent: NativeTextEditor) {
            self.parent = parent
            languageID = parent.languageID
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard parent.isEditable else { return false }
            pendingEdit = .init(
                range: affectedCharRange,
                replacement: replacementString ?? ""
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticChange,
                  let textView = notification.object as? NSTextView else {
                return
            }
            isApplyingUserChange = true
            parent.text = textView.string
            isApplyingUserChange = false
            refreshHighlights()
            pendingEdit = nil
            container?.lineNumberView.needsDisplay = true
            container?.whitespaceOverlayView.needsDisplay = true
            updatePosition(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            updatePosition(in: textView)
            updateCurrentLineHighlight(in: textView)
            showMatchingBracket(in: textView)
        }

        func applyPresentation(to textView: NSTextView) {
            textView.isEditable = parent.isEditable
            textView.isSelectable = true
            textView.isRichText = false
            textView.allowsUndo = true
            textView.font = .monospacedSystemFont(
                ofSize: max(9, min(parent.fontSize, 40)),
                weight: .regular
            )
            textView.textColor = .textColor
            textView.backgroundColor = .textBackgroundColor
            textView.insertionPointColor = .controlAccentColor
            textView.selectedTextAttributes = [
                .backgroundColor: NSColor.selectedTextBackgroundColor,
                .foregroundColor: NSColor.selectedTextColor
            ]
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            textView.textContainerInset = NSSize(width: 10, height: 10)

            if parent.wordWrap {
                textView.isHorizontallyResizable = false
                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.containerSize = NSSize(
                    width: max(0, textView.bounds.width),
                    height: CGFloat.greatestFiniteMagnitude
                )
                container?.scrollView.hasHorizontalScroller = false
            } else {
                textView.isHorizontallyResizable = true
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                container?.scrollView.hasHorizontalScroller = true
            }
        }

        func refreshHighlights() {
            guard let textView = container?.textView else { return }
            let visibleRange = container?.visibleCharacterRange
            let spans = highlighter.highlights(
                in: textView.string,
                edit: pendingEdit,
                visibleRange: visibleRange
            )
            apply(spans, to: textView)
        }

        private func apply(_ spans: [TextHighlightSpan], to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            let font = NSFont.monospacedSystemFont(
                ofSize: max(9, min(parent.fontSize, 40)),
                weight: .regular
            )

            storage.beginEditing()
            storage.setAttributes(
                [
                    .font: font,
                    .foregroundColor: NSColor.textColor
                ],
                range: fullRange
            )
            for span in spans where NSMaxRange(span.range) <= storage.length {
                storage.addAttribute(
                    .foregroundColor,
                    value: color(for: span.role),
                    range: span.range
                )
            }
            storage.endEditing()
            updateCurrentLineHighlight(in: textView)
        }

        private func updateCurrentLineHighlight(in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.backgroundColor, range: fullRange)

            let selection = textView.selectedRange()
            guard parent.isEditable,
                  selection.length == 0,
                  selection.location <= storage.length else {
                return
            }
            let lineRange = (textView.string as NSString).lineRange(
                for: NSRange(location: selection.location, length: 0)
            )
            storage.addAttribute(
                .backgroundColor,
                value: NSColor.selectedContentBackgroundColor.withAlphaComponent(
                    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                        ? 0.18
                        : 0.08
                ),
                range: lineRange
            )
        }

        private func color(for role: SyntaxTokenRole) -> NSColor {
            switch role {
            case .comment:
                .secondaryLabelColor
            case .keyword, .operatorToken:
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(calibratedRed: 0.82, green: 0.60, blue: 1.00, alpha: 1)
                        : NSColor(calibratedRed: 0.53, green: 0.20, blue: 0.70, alpha: 1)
                }
            case .string:
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(calibratedRed: 1.00, green: 0.52, blue: 0.49, alpha: 1)
                        : NSColor(calibratedRed: 0.72, green: 0.13, blue: 0.09, alpha: 1)
                }
            case .number, .constant:
                NSColor.systemOrange
            case .type, .constructor:
                NSColor.systemTeal
            case .function:
                NSColor.systemBlue
            case .property, .variable:
                NSColor.textColor
            case .tag:
                NSColor.systemPink
            case .attribute:
                NSColor.systemIndigo
            case .escape:
                NSColor.systemYellow
            case .label:
                NSColor.systemBrown
            case .embedded:
                NSColor.systemGreen
            case .punctuation:
                NSColor.tertiaryLabelColor
            }
        }

        private func updatePosition(in textView: NSTextView) {
            let selection = textView.selectedRange()
            let string = textView.string as NSString
            let location = min(selection.location, string.length)
            let prefix = string.substring(to: location)
            let line = prefix.reduce(into: 1) { count, character in
                if character == "\n" { count += 1 }
            }
            let lineRange = string.lineRange(
                for: NSRange(location: location, length: 0)
            )
            parent.onPositionChange(
                TextEditorPosition(
                    line: line,
                    column: max(1, location - lineRange.location + 1),
                    selectionLength: selection.length
                )
            )
            reportEditorState()
        }

        func restoreEditorStateIfNeeded(in container: EditorContainerView) {
            guard !didRestoreEditorState else { return }
            didRestoreEditorState = true

            let textLength = container.textView.string.utf16.count
            let location = min(
                max(0, parent.initialEditorState.cursorLocation),
                textLength
            )
            let length = min(
                max(0, parent.initialEditorState.selectionLength),
                textLength - location
            )
            container.textView.setSelectedRange(
                NSRange(location: location, length: length)
            )
            container.layoutSubtreeIfNeeded()
            container.scrollView.contentView.scroll(
                to: NSPoint(
                    x: max(
                        0,
                        parent.initialEditorState.horizontalScrollOffset
                    ),
                    y: max(
                        0,
                        parent.initialEditorState.verticalScrollOffset
                    )
                )
            )
            container.scrollView.reflectScrolledClipView(
                container.scrollView.contentView
            )
            updatePosition(in: container.textView)
        }

        func reportEditorState() {
            guard didRestoreEditorState,
                  let container else {
                return
            }
            let selection = container.textView.selectedRange()
            let origin = container.scrollView.contentView.bounds.origin
            let state = TextEditorState(
                cursorLocation: selection.location,
                selectionLength: selection.length,
                verticalScrollOffset: origin.y,
                horizontalScrollOffset: origin.x
            )
            guard state != lastReportedEditorState else { return }
            lastReportedEditorState = state
            parent.onEditorStateChange(state)
        }

        private func showMatchingBracket(in textView: NSTextView) {
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location > 0 else { return }
            let value = textView.string as NSString
            let location = selection.location - 1
            guard location < value.length else { return }
            let character = value.character(at: location)
            let pairs: [unichar: (unichar, Int)] = [
                0x29: (0x28, -1), // )
                0x5D: (0x5B, -1), // ]
                0x7D: (0x7B, -1), // }
                0x28: (0x29, 1),  // (
                0x5B: (0x5D, 1),  // [
                0x7B: (0x7D, 1)   // {
            ]
            guard let (match, direction) = pairs[character] else { return }

            var depth = 0
            var index = location
            while true {
                let current = value.character(at: index)
                if current == character {
                    depth += 1
                } else if current == match {
                    depth -= 1
                    if depth == 0 {
                        textView.showFindIndicator(
                            for: NSRange(location: index, length: 1)
                        )
                        return
                    }
                }

                if direction < 0 {
                    guard index > 0 else { return }
                    index -= 1
                } else {
                    index += 1
                    guard index < value.length else { return }
                }
            }
        }

        func toggleLineComments() {
            guard parent.isEditable, let textView = container?.textView else { return }
            guard let definition = commentDefinition(for: languageID) else {
                NSSound.beep()
                return
            }
            guard let edit = CommentToggleTransformer.edit(
                in: textView.string,
                selection: textView.selectedRange(),
                definition: definition
            ) else {
                NSSound.beep()
                return
            }
            pendingEdit = .init(
                range: edit.range,
                replacement: edit.replacement
            )
            guard textView.shouldChangeText(
                in: edit.range,
                replacementString: edit.replacement
            ) else {
                pendingEdit = nil
                return
            }
            textView.replaceCharacters(
                in: edit.range,
                with: edit.replacement
            )
            textView.didChangeText()
            textView.setSelectedRange(edit.selection)
            updatePosition(in: textView)
            reportEditorState()
        }

        func goToLine(_ requestedLine: Int) {
            guard let textView = container?.textView else { return }
            let string = textView.string as NSString
            let targetLine = max(1, requestedLine)
            var line = 1
            var location = 0

            while line < targetLine, location < string.length {
                let range = string.lineRange(
                    for: NSRange(location: location, length: 0)
                )
                let next = NSMaxRange(range)
                guard next > location else { break }
                location = next
                line += 1
            }

            textView.setSelectedRange(
                NSRange(location: min(location, string.length), length: 0)
            )
            textView.scrollRangeToVisible(textView.selectedRange())
            textView.window?.makeFirstResponder(textView)
            updatePosition(in: textView)
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard parent.isEditable else { return false }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            let string = textView.string as NSString
            let location = min(textView.selectedRange().location, string.length)
            let lineRange = string.lineRange(
                for: NSRange(location: location, length: 0)
            )
            let beforeCursor = NSRange(
                location: lineRange.location,
                length: max(0, location - lineRange.location)
            )
            let linePrefix = string.substring(with: beforeCursor)
            let indentation = linePrefix.prefix { $0 == " " || $0 == "\t" }
            textView.insertText(
                "\n" + indentation,
                replacementRange: textView.selectedRange()
            )
            return true
        }

        private func commentDefinition(
            for languageID: String
        ) -> LanguageDefinition? {
            let normalized = SyntaxLanguageRegistry.normalized(languageID)
            return LanguageRegistry.builtIn.definition(id: normalized)
        }
    }
}

@MainActor
final class EditorContainerView: NSView {
    let textView: NSTextView
    let scrollView = NSScrollView()
    let lineNumberView: LineNumberView
    let whitespaceOverlayView: WhitespaceOverlayView
    var onScroll: (() -> Void)?
    var showsLineNumbers = true {
        didSet { needsLayout = true }
    }
    var showsWhitespace = false {
        didSet {
            whitespaceOverlayView.isHidden = !showsWhitespace
            whitespaceOverlayView.needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        let textView = NSTextView(usingTextLayoutManager: true)
        self.textView = textView
        lineNumberView = LineNumberView(textView: textView)
        whitespaceOverlayView = WhitespaceOverlayView(textView: textView)
        super.init(frame: frameRect)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        addSubview(lineNumberView)
        addSubview(scrollView)
        addSubview(whitespaceOverlayView)
        whitespaceOverlayView.isHidden = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
        )
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc
    private func contentBoundsDidChange(_ notification: Notification) {
        lineNumberView.needsDisplay = true
        whitespaceOverlayView.needsDisplay = true
        onScroll?()
    }

    override func layout() {
        super.layout()
        let rulerWidth: CGFloat = showsLineNumbers ? 48 : 0
        lineNumberView.isHidden = !showsLineNumbers
        lineNumberView.frame = NSRect(x: 0, y: 0, width: rulerWidth, height: bounds.height)
        scrollView.frame = NSRect(
            x: rulerWidth,
            y: 0,
            width: max(0, bounds.width - rulerWidth),
            height: bounds.height
        )
        whitespaceOverlayView.frame = scrollView.frame
    }

    var visibleCharacterRange: NSRange {
        let visible = scrollView.documentVisibleRect
        let start = textView.characterIndexForInsertion(
            at: NSPoint(x: visible.minX, y: visible.minY)
        )
        let end = textView.characterIndexForInsertion(
            at: NSPoint(x: visible.maxX, y: visible.maxY)
        )
        return NSRange(
            location: min(start, end),
            length: max(0, max(start, end) - min(start, end))
        )
    }
}

@MainActor
final class WhitespaceOverlayView: NSView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView,
              let window = textView.window,
              let container = superview as? EditorContainerView else {
            return
        }

        let value = textView.string as NSString
        let visibleRange = container.visibleCharacterRange
        let start = min(max(0, visibleRange.location), value.length)
        let end = min(max(start, NSMaxRange(visibleRange)), value.length)
        guard start < end else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(
                ofSize: max(8, (textView.font?.pointSize ?? 12) * 0.72),
                weight: .regular
            ),
            .foregroundColor: NSColor.tertiaryLabelColor.withAlphaComponent(0.75)
        ]

        for location in start..<end {
            let unit = value.character(at: location)
            let marker: NSString
            switch unit {
            case 0x20:
                marker = "·"
            case 0x09:
                marker = "→"
            case 0x0A, 0x0D:
                marker = "↵"
            default:
                continue
            }

            var actualRange = NSRange()
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: location, length: 1),
                actualRange: &actualRange
            )
            guard !screenRect.isEmpty else { continue }
            let windowRect = window.convertFromScreen(screenRect)
            let localRect = convert(windowRect, from: nil)
            marker.draw(
                at: NSPoint(
                    x: localRect.minX + 1,
                    y: localRect.midY - marker.size(withAttributes: attributes).height / 2
                ),
                withAttributes: attributes
            )
        }
    }
}

@MainActor
final class LineNumberView: NSView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()
        guard let textView,
              let scrollView = textView.enclosingScrollView else {
            return
        }

        let visible = scrollView.documentVisibleRect
        let string = textView.string as NSString
        let start = min(
            textView.characterIndexForInsertion(
                at: NSPoint(x: visible.minX, y: visible.minY)
            ),
            string.length
        )
        let end = min(
            textView.characterIndexForInsertion(
                at: NSPoint(x: visible.maxX, y: visible.maxY)
            ),
            string.length
        )
        let firstLineRange = string.lineRange(
            for: NSRange(location: start, length: 0)
        )
        var characterIndex = firstLineRange.location
        var lineNumber = 1 + string.substring(to: characterIndex).reduce(into: 0) {
            if $1 == "\n" { $0 += 1 }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        while characterIndex <= max(start, end), characterIndex <= string.length {
            var actualRange = NSRange()
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: characterIndex, length: 0),
                actualRange: &actualRange
            )
            if let window = textView.window {
                let windowRect = window.convertFromScreen(screenRect)
                let localRect = convert(windowRect, from: nil)
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(
                    at: NSPoint(
                        x: bounds.width - size.width - 8,
                        y: localRect.minY
                    ),
                    withAttributes: attributes
                )
            }

            guard characterIndex < string.length else { break }
            let lineRange = string.lineRange(
                for: NSRange(location: characterIndex, length: 0)
            )
            let nextIndex = NSMaxRange(lineRange)
            guard nextIndex > characterIndex else { break }
            characterIndex = nextIndex
            lineNumber += 1
        }
    }
}

struct TextEditorStatusBar: View {
    let languageName: String
    let encodingName: String
    let lineEndingName: String
    let indentationName: String
    let position: TextEditorPosition
    let fileSize: Int64
    let isEditable: Bool
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 14) {
            Label(
                isEditable ? "Editing" : "Read Only",
                systemImage: isEditable ? "pencil" : "eye"
            )
            .foregroundStyle(isEditable ? .primary : .secondary)

            if isDirty {
                Label(
                    "Unsaved Changes",
                    systemImage: "exclamationmark.circle.fill"
                )
                .foregroundStyle(.primary)
            }

            Spacer()

            Text(languageName)
            Text(encodingName)
            Text(lineEndingName)
            Text(indentationName)
            Text(position.selectionLength > 0
                 ? "\(position.selectionLength) selected"
                 : "Ln \(position.line), Col \(position.column)")
            Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 25)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

struct TextEditorPane: View {
    @Binding var text: String
    let languageID: String
    let encodingName: String
    let lineEndingName: String
    let fileSize: Int64
    var canEdit = true
    @Binding var isEditing: Bool
    @Binding var wordWrap: Bool
    @Binding var fontSize: CGFloat
    var onSave: (() -> Void)?
    let isDirty: Bool
    let initialEditorState: TextEditorState
    let onEditorStateChange: (TextEditorState) -> Void

    @State private var position = TextEditorPosition()
    @State private var findRequest = 0
    @State private var commentRequest = 0
    @State private var goToLineRequest = 0
    @State private var goToLineText = "1"
    @State private var showsGoToLine = false
    @State private var showsWhitespace = false
    @State private var manualLanguageID: String?

    private var effectiveLanguageID: String {
        canEdit ? (manualLanguageID ?? languageID) : languageID
    }

    private var canToggleComment: Bool {
        guard let definition = LanguageRegistry.builtIn.definition(
            id: SyntaxLanguageRegistry.normalized(effectiveLanguageID)
        ) else {
            return false
        }
        return definition.lineComment != nil || definition.blockComment != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if canEdit {
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                    .keyboardShortcut("e", modifiers: .command)
                }

                Button {
                    findRequest &+= 1
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)

                Menu {
                    Button {
                        manualLanguageID = nil
                    } label: {
                        Label(
                            "Automatic — \(SyntaxLanguageRegistry.displayName(for: languageID))",
                            systemImage: manualLanguageID == nil
                                ? "checkmark"
                                : "wand.and.stars"
                        )
                    }
                    Divider()
                    ForEach(SyntaxLanguageRegistry.bundledLanguages) { language in
                        Button {
                            manualLanguageID = language.id
                        } label: {
                            Label(
                                language.displayName,
                                systemImage: manualLanguageID == language.id
                                    ? "checkmark"
                                    : "chevron.left.forwardslash.chevron.right"
                            )
                        }
                    }
                } label: {
                    Label(
                        "Language",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }
                .disabled(!canEdit)
                .help("Choose syntax language")

                Toggle("Wrap", isOn: $wordWrap)
                    .toggleStyle(.button)
                    .disabled(!canEdit)

                Button {
                    commentRequest &+= 1
                } label: {
                    Label("Toggle Comment", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .keyboardShortcut("/", modifiers: .command)
                .disabled(!canEdit || !isEditing || !canToggleComment)

                Toggle("Show Whitespace", isOn: $showsWhitespace)
                    .toggleStyle(.button)
                    .disabled(!canEdit)

                Button {
                    goToLineText = String(position.line)
                    showsGoToLine = true
                } label: {
                    Label("Go to Line", systemImage: "arrow.down.to.line")
                }
                .keyboardShortcut("g", modifiers: .control)
                .popover(isPresented: $showsGoToLine) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Go to Line")
                            .font(.headline)
                        TextField("Line number", text: $goToLineText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onSubmit(performGoToLine)
                        HStack {
                            Spacer()
                            Button("Go", action: performGoToLine)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(14)
                }

                Spacer()

                Button {
                    fontSize = max(9, fontSize - 1)
                } label: {
                    Label("Smaller Text", systemImage: "textformat.size.smaller")
                }

                Button {
                    fontSize = min(40, fontSize + 1)
                } label: {
                    Label("Larger Text", systemImage: "textformat.size.larger")
                }
            }
            .labelStyle(.iconOnly)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(.bar)

            Divider()

            NativeTextEditor(
                text: $text,
                languageID: effectiveLanguageID,
                isEditable: canEdit && isEditing,
                wordWrap: wordWrap,
                fontSize: fontSize,
                showsWhitespace: showsWhitespace,
                findRequest: findRequest,
                commentRequest: commentRequest,
                goToLineRequest: goToLineRequest,
                goToLineNumber: Int(goToLineText) ?? 1,
                initialEditorState: initialEditorState,
                onPositionChange: { position = $0 },
                onEditorStateChange: onEditorStateChange,
                onSave: onSave
            )

            Divider()

            TextEditorStatusBar(
                languageName: SyntaxLanguageRegistry.displayName(
                    for: effectiveLanguageID
                ),
                encodingName: encodingName,
                lineEndingName: lineEndingName,
                indentationName: TextIndentationDetector.description(
                    for: text
                ),
                position: position,
                fileSize: fileSize,
                isEditable: canEdit && isEditing,
                isDirty: isDirty
            )
        }
        .onChange(of: languageID) { _, _ in
            manualLanguageID = nil
        }
    }

    private func performGoToLine() {
        guard let line = Int(goToLineText), line > 0 else {
            NSSound.beep()
            return
        }
        goToLineRequest &+= 1
        showsGoToLine = false
    }
}

enum TextIndentationDetector {
    static func description(for text: String) -> String {
        var tabIndentedLines = 0
        var spaceWidths: [Int: Int] = [:]

        for line in text.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        ).prefix(2_000) {
            guard let first = line.first else { continue }
            if first == "\t" {
                tabIndentedLines += 1
                continue
            }
            guard first == " " else { continue }
            let width = line.prefix(while: { $0 == " " }).count
            guard width > 0 else { continue }
            let normalizedWidth = [2, 4, 8].min {
                abs($0 - width) < abs($1 - width)
            } ?? width
            spaceWidths[normalizedWidth, default: 0] += 1
        }

        let dominantSpaces = spaceWidths.max {
            if $0.value != $1.value {
                return $0.value < $1.value
            }
            return $0.key > $1.key
        }
        if tabIndentedLines > (dominantSpaces?.value ?? 0) {
            return "Tabs"
        }
        if let dominantSpaces {
            return "Spaces: \(dominantSpaces.key)"
        }
        return "No indentation"
    }
}
