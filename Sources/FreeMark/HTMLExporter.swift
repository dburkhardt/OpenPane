import Foundation

enum HTMLExporter {
    static func export(model: MarkdownModel, title: String, to url: URL) throws {
        let body = model.blocks.map(render).joined(separator: "\n")
        let document = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escape(title))</title>
          <style>
            :root { color-scheme: light dark; }
            body { font: 17px/1.6 -apple-system, BlinkMacSystemFont, sans-serif;
                   max-width: 760px; margin: 48px auto; padding: 0 28px; }
            pre { overflow-x: auto; padding: 16px; border-radius: 9px;
                  background: color-mix(in srgb, CanvasText 8%, Canvas); }
            code { font-family: ui-monospace, SFMono-Regular, monospace; }
            blockquote { border-left: 3px solid #888; margin-left: 0;
                         padding-left: 16px; color: #777; }
            img { max-width: 100%; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
        try document.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func render(_ block: MarkdownModel.Block) -> String {
        switch block {
        case .heading(let heading):
            return "<h\(heading.level)>\(inline(heading.title))</h\(heading.level)>"
        case .paragraph(_, let text):
            return "<p>\(inline(text).replacingOccurrences(of: "\n", with: "<br>"))</p>"
        case .quote(_, let text):
            return "<blockquote>\(inline(text))</blockquote>"
        case .bullet(_, let text, let checked):
            let marker = checked.map { $0 ? "☑︎ " : "☐ " } ?? ""
            return "<ul><li>\(marker)\(inline(text))</li></ul>"
        case .code(_, let language, let source):
            let languageClass = language.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre><code\(languageClass)>\(escape(source))</code></pre>"
        case .divider:
            return "<hr>"
        case .blank:
            return ""
        }
    }

    private static func inline(_ source: String) -> String {
        var result = escape(source)
        let replacements = [
            (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
            (#"__(.+?)__"#, "<strong>$1</strong>"),
            (#"\*(.+?)\*"#, "<em>$1</em>"),
            (#"`(.+?)`"#, "<code>$1</code>"),
            (#"\[(.+?)\]\((.+?)\)"#, "<a href=\"$2\">$1</a>")
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(
                of: pattern,
                with: template,
                options: .regularExpression
            )
        }
        return result
    }

    private static func escape(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
