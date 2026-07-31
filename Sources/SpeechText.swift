import Foundation

/// Turns pasted text — markdown, bullet lists, hard-wrapped paragraphs — into the clean
/// sentences the model expects. Everything here is about prosody: the chunker splits on
/// sentence punctuation, so a line that is really a sentence has to end like one, and a
/// line that is merely a wrap must not.
enum SpeechText {
    static func normalized(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map(cleaned)
        var result: [String] = []
        for (index, line) in lines.enumerated() where !line.text.isEmpty {
            let rest = lines[(index + 1)...]
            let next = rest.first { !$0.text.isEmpty }
            let continues = !line.isBlock
                && !(rest.first?.text.isEmpty ?? true)
                && next.map { !$0.isBlock && startsMidSentence($0.text) } ?? false
            result.append(endsSentence(line.text) || continues ? line.text : line.text + ".")
        }
        return result.joined(separator: " ")
    }

    /// A heading, quote or list item: its own sentence no matter how it ends.
    private static let blockMarker = regex("^\\s*(?:[>#]+|[-*+•]|\\d+[.)])\\s+")

    private static let rules: [(NSRegularExpression, String)] = [
        ("[\\p{Cc}\\p{Cf}]", " "),                              // control and zero-width
        ("!?\\[([^\\]]*)\\]\\([^)]*\\)", "$1"),                 // markdown links
        ("\\bhttps?://(?:www\\.)?([^\\s/]+)\\S*", "$1"),        // bare URLs read as their host
        ("(^|[\\s(])[*_~`]{1,3}(?=\\S)", "$1"),                 // emphasis, opening
        ("(?<=\\S)[*_~`]{1,3}(?=[\\s).,!?;:]|$)", ""),          // emphasis, closing
        ("\\s+", " "),
    ].map { (regex($0.0), $0.1) }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals; a failure here would be a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    private static func cleaned(_ line: String) -> (text: String, isBlock: Bool) {
        var value = replacing(line, with: blockMarker, template: "")
        let isBlock = value != line
        for (regex, template) in rules {
            value = replacing(value, with: regex, template: template)
        }
        return (value.trimmingCharacters(in: .whitespaces), isBlock)
    }

    private static func replacing(
        _ value: String,
        with regex: NSRegularExpression,
        template: String
    ) -> String {
        regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }

    private static func endsSentence(_ line: String) -> Bool {
        guard let last = line.last(where: { !")\"»'”]".contains($0) }) else { return false }
        return ".!?:;…".contains(last)
    }

    /// A continuation of the previous line rather than a new one — a hard-wrapped paragraph.
    private static func startsMidSentence(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        return first.isLowercase || first == ","
    }
}
