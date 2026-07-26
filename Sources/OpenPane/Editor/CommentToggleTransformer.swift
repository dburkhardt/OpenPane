import Foundation
import OpenPaneCore

struct CommentToggleEdit: Equatable {
    let range: NSRange
    let replacement: String
    let selection: NSRange
}

enum CommentToggleTransformer {
    static func edit(
        in text: String,
        selection: NSRange,
        definition: LanguageDefinition
    ) -> CommentToggleEdit? {
        let source = text as NSString
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.length >= 0,
              selection.location <= source.length,
              selection.length <= source.length - selection.location else {
            return nil
        }

        if let prefix = definition.lineComment {
            return lineCommentEdit(
                in: source,
                selection: selection,
                prefix: prefix
            )
        }
        if let blockComment = definition.blockComment {
            return blockCommentEdit(
                in: source,
                selection: selection,
                comment: blockComment
            )
        }
        return nil
    }

    private static func lineCommentEdit(
        in source: NSString,
        selection: NSRange,
        prefix: String
    ) -> CommentToggleEdit {
        let linesRange = source.lineRange(
            for: lineSelectionRange(selection)
        )
        let lines = source.substring(with: linesRange)
            .components(separatedBy: "\n")
        let nonEmpty = lines.filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let shouldUncomment = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
        }
        let transformed = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
                return line
            }
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            var content = String(line.dropFirst(indentation.count))
            if shouldUncomment {
                content.removeFirst(min(prefix.count, content.count))
                if content.first == " " {
                    content.removeFirst()
                }
            } else {
                content = prefix + " " + content
            }
            return String(indentation) + content
        }.joined(separator: "\n")

        let transformedLength = transformed.utf16.count
        let adjustedSelection: NSRange
        if selection.length > 0 {
            adjustedSelection = NSRange(
                location: linesRange.location,
                length: transformedLength
            )
        } else {
            let line = source.substring(with: linesRange)
            let indentationLength = line.prefix {
                $0 == " " || $0 == "\t"
            }.utf16.count
            let changeLocation = linesRange.location + indentationLength
            let relativeChangeLength: Int
            if shouldUncomment {
                let content = String(line.dropFirst(indentationLength))
                relativeChangeLength = prefix.utf16.count
                    + (content.dropFirst(prefix.count).first == " " ? 1 : 0)
            } else {
                relativeChangeLength = prefix.utf16.count + 1
            }
            let location: Int
            if selection.location < changeLocation {
                location = selection.location
            } else if shouldUncomment {
                location = max(
                    changeLocation,
                    selection.location - relativeChangeLength
                )
            } else {
                location = selection.location + relativeChangeLength
            }
            adjustedSelection = NSRange(
                location: min(
                    location,
                    linesRange.location + transformedLength
                ),
                length: 0
            )
        }

        return CommentToggleEdit(
            range: linesRange,
            replacement: transformed,
            selection: adjustedSelection
        )
    }

    private static func blockCommentEdit(
        in source: NSString,
        selection: NSRange,
        comment: BlockComment
    ) -> CommentToggleEdit {
        let range = selection.length > 0
            ? selection
            : source.lineRange(for: selection)
        let original = source.substring(with: range)
        let trimmed = original.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmed.hasPrefix(comment.opening),
           trimmed.hasSuffix(comment.closing),
           trimmed.utf16.count
                >= comment.opening.utf16.count + comment.closing.utf16.count {
            return blockUncommentEdit(
                original: original,
                range: range,
                selection: selection,
                trimmed: trimmed,
                comment: comment
            )
        }

        let (body, trailingLineEnding) = splitTrailingLineEnding(original)
        let replacement: String
        let insertionLocation: Int
        let insertedPrefixLength: Int

        if containsLineEnding(body) {
            let wrapperLineEnding = firstLineEnding(in: body) ?? "\n"
            replacement = comment.opening
                + wrapperLineEnding
                + body
                + wrapperLineEnding
                + comment.closing
                + trailingLineEnding
            insertionLocation = 0
            insertedPrefixLength = comment.opening.utf16.count
                + wrapperLineEnding.utf16.count
        } else {
            let indentation = body.prefix { $0 == " " || $0 == "\t" }
            let content = String(body.dropFirst(indentation.count))
            let spacing = content.isEmpty ? "" : " "
            replacement = String(indentation)
                + comment.opening
                + spacing
                + content
                + spacing
                + comment.closing
                + trailingLineEnding
            insertionLocation = indentation.utf16.count
            insertedPrefixLength = comment.opening.utf16.count
                + spacing.utf16.count
        }

        let replacementLength = replacement.utf16.count
        let adjustedSelection: NSRange
        if selection.length > 0 {
            adjustedSelection = NSRange(
                location: range.location,
                length: replacementLength
            )
        } else {
            let relativeLocation = selection.location - range.location
            let location = relativeLocation < insertionLocation
                ? relativeLocation
                : relativeLocation + insertedPrefixLength
            adjustedSelection = NSRange(
                location: range.location + min(location, replacementLength),
                length: 0
            )
        }

        return CommentToggleEdit(
            range: range,
            replacement: replacement,
            selection: adjustedSelection
        )
    }

    private static func blockUncommentEdit(
        original: String,
        range: NSRange,
        selection: NSRange,
        trimmed: String,
        comment: BlockComment
    ) -> CommentToggleEdit {
        let originalNSString = original as NSString
        let trimmedRange = originalNSString.range(of: trimmed)
        let leading = originalNSString.substring(
            with: NSRange(location: 0, length: trimmedRange.location)
        )
        let trailingStart = NSMaxRange(trimmedRange)
        let trailing = originalNSString.substring(
            with: NSRange(
                location: trailingStart,
                length: originalNSString.length - trailingStart
            )
        )

        var content = String(
            trimmed.dropFirst(comment.opening.count)
                .dropLast(comment.closing.count)
        )
        let leadingWrapperLineEnding = leadingLineEnding(in: content)
        let trailingWrapperLineEnding = trailingLineEnding(in: content)
        let removedPrefixLength: Int

        if let leadingWrapperLineEnding,
           let trailingWrapperLineEnding {
            content.removeFirst(leadingWrapperLineEnding.count)
            content.removeLast(trailingWrapperLineEnding.count)
            removedPrefixLength = comment.opening.utf16.count
                + leadingWrapperLineEnding.utf16.count
        } else {
            let hadLeadingSpace = content.first == " "
            if hadLeadingSpace {
                content.removeFirst()
            }
            if content.last == " " {
                content.removeLast()
            }
            removedPrefixLength = comment.opening.utf16.count
                + (hadLeadingSpace ? 1 : 0)
        }

        let replacement = leading + content + trailing
        let replacementLength = replacement.utf16.count
        let adjustedSelection: NSRange
        if selection.length > 0 {
            adjustedSelection = NSRange(
                location: range.location,
                length: replacementLength
            )
        } else {
            let relativeLocation = selection.location - range.location
            let contentStart = trimmedRange.location + removedPrefixLength
            let location: Int
            if relativeLocation <= trimmedRange.location {
                location = relativeLocation
            } else if relativeLocation < contentStart {
                location = trimmedRange.location
            } else {
                location = relativeLocation - removedPrefixLength
            }
            adjustedSelection = NSRange(
                location: range.location + min(location, replacementLength),
                length: 0
            )
        }

        return CommentToggleEdit(
            range: range,
            replacement: replacement,
            selection: adjustedSelection
        )
    }

    private static func lineSelectionRange(_ selection: NSRange) -> NSRange {
        guard selection.length > 0 else { return selection }
        return NSRange(
            location: selection.location,
            length: selection.length - 1
        )
    }

    private static func splitTrailingLineEnding(
        _ text: String
    ) -> (body: String, lineEnding: String) {
        if text.hasSuffix("\r\n") {
            return (String(text.dropLast(2)), "\r\n")
        }
        if text.hasSuffix("\n") {
            return (String(text.dropLast()), "\n")
        }
        if text.hasSuffix("\r") {
            return (String(text.dropLast()), "\r")
        }
        return (text, "")
    }

    private static func containsLineEnding(_ text: String) -> Bool {
        text.contains("\n") || text.contains("\r")
    }

    private static func firstLineEnding(in text: String) -> String? {
        for index in text.indices {
            if text[index] == "\n" {
                return "\n"
            }
            if text[index] == "\r" {
                let next = text.index(after: index)
                return next < text.endIndex && text[next] == "\n"
                    ? "\r\n"
                    : "\r"
            }
        }
        return nil
    }

    private static func leadingLineEnding(in text: String) -> String? {
        if text.hasPrefix("\r\n") {
            return "\r\n"
        }
        if text.hasPrefix("\n") {
            return "\n"
        }
        if text.hasPrefix("\r") {
            return "\r"
        }
        return nil
    }

    private static func trailingLineEnding(in text: String) -> String? {
        if text.hasSuffix("\r\n") {
            return "\r\n"
        }
        if text.hasSuffix("\n") {
            return "\n"
        }
        if text.hasSuffix("\r") {
            return "\r"
        }
        return nil
    }
}
