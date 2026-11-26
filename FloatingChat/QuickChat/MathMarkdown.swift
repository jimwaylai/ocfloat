import Foundation
@_spi(Textual) import SwiftUIMath
import Textual

/// Finds LaTeX formulas in Markdown before the Markdown parser sees them, so backslashes,
/// `_` and `*` inside a formula survive and a lone `$` (currency) stays plain text.
enum MathMarkdown {
    struct Formula: Equatable {
        let latex: String
        let isBlock: Bool
        /// The formula as written, shown if it cannot be rendered.
        let source: String
    }

    /// swiftui-math lays out a formula it cannot parse as zero-sized and draws nothing.
    static func canRender(_ formula: Formula) -> Bool {
        Math.typographicBounds(
            for: formula.latex,
            fitting: .unspecified,
            font: .init(name: .latinModern, size: 16),
            style: formula.isBlock ? .display : .text
        ).width > 0
    }

    /// Survives Markdown parsing untouched: private-use characters and digits have no syntax.
    static func placeholder(_ index: Int) -> String {
        "\u{E000}\(index)\u{E001}"
    }

    /// Replaces `$$…$$`, `\[…\]`, `$…$` and `\(…\)` outside code with placeholders.
    /// Inline `$…$` follows Pandoc: no space after the opening `$` or before the closing one,
    /// and no digit right after it, so "$5 and $10" is not a formula.
    static func extract(_ markdown: String) -> (text: String, formulas: [Formula]) {
        let chars = Array(markdown)
        var text = ""
        var formulas: [Formula] = []
        var index = 0
        var atLineStart = true

        func add(_ latex: [Character], isBlock: Bool, source: ArraySlice<Character>) {
            text += placeholder(formulas.count)
            formulas.append(Formula(latex: normalize(String(latex)), isBlock: isBlock, source: String(source)))
            atLineStart = false
        }

        while index < chars.count {
            if atLineStart, let end = fencedCodeEnd(chars, from: index) {
                text += String(chars[index..<end])
                index = end
                continue
            }
            let char = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil

            if char == "`" {
                let end = inlineCodeEnd(chars, from: index)
                text += String(chars[index..<end])
                index = end
                atLineStart = false
                continue
            }
            if char == "\\", let next {
                if next == "[" || next == "(" {
                    let closing: [Character] = ["\\", next == "[" ? "]" : ")"]
                    if let close = find(closing, in: chars, from: index + 2), close > index + 2 {
                        add(Array(chars[(index + 2)..<close]), isBlock: next == "[", source: chars[index..<(close + 2)])
                        index = close + 2
                        continue
                    }
                }
                text.append(char)
                text.append(next)
                index += 2
                atLineStart = next.isNewline
                continue
            }
            if char == "$", next == "$" {
                if let close = find(["$", "$"], in: chars, from: index + 2),
                   !String(chars[(index + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(Array(chars[(index + 2)..<close]), isBlock: true, source: chars[index..<(close + 2)])
                    index = close + 2
                } else {
                    text += "$$"
                    index += 2
                    atLineStart = false
                }
                continue
            }
            if char == "$", let close = inlineMathEnd(chars, from: index) {
                add(Array(chars[(index + 1)..<close]), isBlock: false, source: chars[index...close])
                index = close + 1
                continue
            }
            text.append(char)
            atLineStart = char.isNewline
            index += 1
        }
        return (text, formulas)
    }

    /// swiftui-math knows `aligned` but not `align`.
    private static func normalize(_ latex: String) -> String {
        rewriteUnsupported(latex)
            .replacingOccurrences(of: "\\begin{align*}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align*}", with: "\\end{aligned}")
            .replacingOccurrences(of: "\\begin{align}", with: "\\begin{aligned}")
            .replacingOccurrences(of: "\\end{align}", with: "\\end{aligned}")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commands models use that swiftui-math does not know, mapped to ones it does.
    /// A formula with an unknown command renders as nothing at all.
    private static let renamed: [String: String] = [
        "operatorname": "\\mathrm",
        "dots": "\\ldots", "dotso": "\\ldots", "dotsc": "\\ldots", "ldotp": "\\ldots",
        "dotsb": "\\cdots", "dotsm": "\\cdots", "dotsi": "\\cdots",
        "lvert": "\\vert", "rvert": "\\vert", "lVert": "\\Vert", "rVert": "\\Vert",
        "varnothing": "\\emptyset",
        "boldsymbol": "\\bm",
        "enspace": "\\;",
        "bmod": "\\;\\mathrm{mod}\\;",
    ]

    /// Decorations and sizing hints dropped, keeping what they apply to.
    private static let dropped: Set<String> = [
        "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr",
        "biggl", "biggr", "Biggl", "Biggr", "bigm", "Bigm", "middle",
        "boxed", "cancel", "underbrace", "overbrace", "nonumber", "notag",
    ]

    private static func rewriteUnsupported(_ latex: String) -> String {
        let chars = Array(latex)
        var output = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == "\\", index + 1 < chars.count else {
                output.append(chars[index])
                index += 1
                continue
            }
            guard chars[index + 1].isASCII, chars[index + 1].isLetter else {
                // Copy escapes like `\\` and `\{` whole so the second character is not reread.
                output.append(chars[index])
                output.append(chars[index + 1])
                index += 2
                continue
            }
            var end = index + 1
            while end < chars.count, chars[end].isASCII, chars[end].isLetter { end += 1 }
            let name = String(chars[(index + 1)..<end])
            if name == "operatorname", end < chars.count, chars[end] == "*" { end += 1 }
            index = end

            if let replacement = renamed[name] {
                output += replacement
            } else if dropped.contains(name) {
                continue
            } else if name == "tag" || name == "label" {
                _ = argument(chars, &index)
            } else if name == "underset" || name == "overset" || name == "stackrel" {
                let script = rewriteUnsupported(argument(chars, &index))
                let base = rewriteUnsupported(argument(chars, &index))
                output += "{\(base)}\(name == "underset" ? "_" : "^"){\(script)}"
            } else if name == "xrightarrow" || name == "xleftarrow" {
                _ = optionalArgument(chars, &index)
                let label = rewriteUnsupported(argument(chars, &index))
                output += "\(name == "xrightarrow" ? "\\rightarrow" : "\\leftarrow")^{\(label)}"
            } else {
                output += "\\" + name
            }
        }
        return output
    }

    /// Reads a `{…}` group or a single token, returning its contents.
    private static func argument(_ chars: [Character], _ index: inout Int) -> String {
        while index < chars.count, chars[index].isWhitespace { index += 1 }
        guard index < chars.count else { return "" }
        if chars[index] == "{" {
            var depth = 0
            let start = index + 1
            while index < chars.count {
                switch chars[index] {
                case "\\": index += 1
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        defer { index += 1 }
                        return String(chars[start..<index])
                    }
                default: break
                }
                index += 1
            }
            return String(chars[start..<chars.count])
        }
        if chars[index] == "\\" {
            let start = index
            index += 1
            if index < chars.count, chars[index].isASCII, chars[index].isLetter {
                while index < chars.count, chars[index].isASCII, chars[index].isLetter { index += 1 }
            } else {
                index = min(index + 1, chars.count)
            }
            return String(chars[start..<index])
        }
        defer { index += 1 }
        return String(chars[index])
    }

    private static func optionalArgument(_ chars: [Character], _ index: inout Int) -> String? {
        var probe = index
        while probe < chars.count, chars[probe].isWhitespace { probe += 1 }
        guard probe < chars.count, chars[probe] == "[",
              let close = chars[probe...].firstIndex(of: "]") else { return nil }
        index = close + 1
        return String(chars[(probe + 1)..<close])
    }

    /// The index just past a fenced code block starting at `start`, or nil if none starts there.
    /// An unclosed fence (still streaming) runs to the end.
    private static func fencedCodeEnd(_ chars: [Character], from start: Int) -> Int? {
        guard let (fence, count, afterFence) = fenceOpening(chars, at: start) else { return nil }
        var line = lineEnd(chars, from: afterFence)
        while line < chars.count {
            if let (closing, closingCount, afterClosing) = fenceOpening(chars, at: line),
               closing == fence, closingCount >= count {
                return lineEnd(chars, from: afterClosing)
            }
            line = lineEnd(chars, from: line)
        }
        return chars.count
    }

    private static func fenceOpening(_ chars: [Character], at start: Int) -> (Character, Int, Int)? {
        var index = start
        while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
        guard index < chars.count, chars[index] == "`" || chars[index] == "~" else { return nil }
        let fence = chars[index]
        var count = 0
        while index < chars.count, chars[index] == fence { count += 1; index += 1 }
        return count >= 3 ? (fence, count, index) : nil
    }

    /// The index just past the next newline, or the end.
    private static func lineEnd(_ chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count, !chars[index].isNewline { index += 1 }
        return min(index + 1, chars.count)
    }

    /// A code span closes with a backtick run of the same length; unmatched backticks are literal.
    private static func inlineCodeEnd(_ chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count, chars[index] == "`" { index += 1 }
        let length = index - start
        while index < chars.count {
            guard chars[index] == "`" else { index += 1; continue }
            let runStart = index
            while index < chars.count, chars[index] == "`" { index += 1 }
            if index - runStart == length { return index }
        }
        return start + length
    }

    private static func inlineMathEnd(_ chars: [Character], from start: Int) -> Int? {
        let first = start + 1
        guard first < chars.count, !chars[first].isWhitespace, chars[first] != "$" else { return nil }
        var index = first
        while index < chars.count, !chars[index].isNewline {
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == "$" {
                let followedByDigit = index + 1 < chars.count && chars[index + 1].isASCII && chars[index + 1].isNumber
                guard !chars[index - 1].isWhitespace, !followedByDigit else { return nil }
                return index
            }
            index += 1
        }
        return nil
    }

    private static func find(_ needle: [Character], in chars: [Character], from start: Int) -> Int? {
        guard needle.count <= chars.count else { return nil }
        var index = start
        while index + needle.count <= chars.count {
            if chars[index..<(index + needle.count)].elementsEqual(needle) { return index }
            index += 1
        }
        return nil
    }
}

/// Markdown with LaTeX formulas, rendered by Textual's math attachments.
struct MathMarkdownParser: MarkupParser {
    private typealias AttachmentKey = AttributeScopes.TextualAttributes.AttachmentAttribute

    func attributedString(for input: String) throws -> AttributedString {
        let (text, formulas) = MathMarkdown.extract(input)
        var output = try AttributedStringMarkdownParser.markdown().attributedString(for: text)
        for (index, formula) in formulas.enumerated().reversed() {
            guard let range = output.range(of: MathMarkdown.placeholder(index)) else { continue }
            var attributes = output[range].runs.first?.attributes ?? AttributeContainer()
            let replacement: AttributedString
            if let attachment = try Self.attachment(for: formula) {
                attributes[AttachmentKey.self] = attachment
                replacement = AttributedString("\u{FFFC}", attributes: attributes)
            } else {
                replacement = AttributedString(formula.source, attributes: attributes)
            }
            output.replaceSubrange(range, with: replacement)
        }
        return output
    }

    /// Textual only builds math attachments from Markdown, so the formula goes through its
    /// parser on its own, escaped so Markdown hands the LaTeX over unchanged.
    private static func attachment(for formula: MathMarkdown.Formula) throws -> AnyAttachment? {
        guard MathMarkdown.canRender(formula) else { return nil }
        let lines = formula.latex
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var escaped = ""
        for char in lines.joined(separator: "\n") {
            if char.isASCII, char.isPunctuation || char.isSymbol { escaped.append("\\") }
            escaped.append(char)
        }
        let delimiter = formula.isBlock ? "$$" : "$"
        let parsed = try AttributedStringMarkdownParser.markdown(syntaxExtensions: [.math])
            .attributedString(for: delimiter + escaped + delimiter)
        return parsed.runs[AttachmentKey.self].lazy.compactMap(\.0).first
    }
}
