import Foundation
import SwiftUI

struct ProofreadingIssue: Identifiable, Equatable {
    enum Kind: String {
        case longSentence = "Long sentence"
        case repeatedWord = "Repeated word"
        case hedge = "Hedge"
        case passiveVoice = "Possible passive voice"
    }

    let id = UUID()
    let kind: Kind
    let excerpt: String
    let suggestion: String
}

enum Proofreader {
    static func inspect(_ source: String) -> [ProofreadingIssue] {
        let plain = source
            .replacingOccurrences(of: #"```[\s\S]*?```"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[#>*_`\[\]\(\)]"#, with: " ", options: .regularExpression)
        var issues: [ProofreadingIssue] = []

        let sentences = plain.split(whereSeparator: { ".!?".contains($0) })
        for sentence in sentences {
            let words = sentence.split(whereSeparator: \.isWhitespace)
            if words.count > 32 {
                issues.append(
                    .init(
                        kind: .longSentence,
                        excerpt: excerpt(String(sentence)),
                        suggestion: "Consider splitting this sentence."
                    )
                )
            }
        }

        matches(in: plain, pattern: #"\b(\w+)\s+\1\b"#).forEach {
            issues.append(
                .init(
                    kind: .repeatedWord,
                    excerpt: excerpt($0),
                    suggestion: "Remove the repeated word."
                )
            )
        }

        matches(
            in: plain,
            pattern: #"\b(might|maybe|perhaps|possibly|somewhat|kind of|sort of)\b"#
        ).forEach {
            issues.append(
                .init(
                    kind: .hedge,
                    excerpt: excerpt($0),
                    suggestion: "Use a more direct phrase when the evidence allows it."
                )
            )
        }

        matches(
            in: plain,
            pattern: #"\b(is|are|was|were|be|been|being)\s+\w+(ed|en)\b"#
        ).forEach {
            issues.append(
                .init(
                    kind: .passiveVoice,
                    excerpt: excerpt($0),
                    suggestion: "Check whether an active construction is clearer."
                )
            )
        }

        return issues
    }

    private static func matches(in source: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return expression.matches(in: source, range: range).compactMap {
            guard let swiftRange = Range($0.range, in: source) else { return nil }
            return String(source[swiftRange])
        }
    }

    private static func excerpt(_ value: String) -> String {
        let compact = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return compact.count > 110 ? String(compact.prefix(107)) + "…" : compact
    }
}

struct ProofreaderView: View {
    let source: String

    private var issues: [ProofreadingIssue] { Proofreader.inspect(source) }
    private var wordCount: Int { source.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Proofreader")
                    .font(.headline)
                Spacer()
                Text("\(wordCount) words")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if issues.isEmpty {
                ContentUnavailableView(
                    "No Suggestions",
                    systemImage: "checkmark.circle",
                    description: Text("The local checks didn’t find obvious issues.")
                )
            } else {
                List(issues) { issue in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(issue.kind.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(issue.excerpt)
                            .font(.callout)
                        Text(issue.suggestion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }
}
