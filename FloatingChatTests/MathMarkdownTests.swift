import Testing
@testable import FloatingChat

struct MathMarkdownTests {
    private func formulas(_ markdown: String) -> [MathMarkdown.Formula] {
        MathMarkdown.extract(markdown).formulas
    }

    @Test func blockFormulaKeepsLaTeXIntact() {
        let latex = #"\zeta(s) = 2^s \pi^{s-1} \sin\!\left(\frac{\pi s}{2}\right) \Gamma(1-s)\,\zeta(1-s)"#
        let (text, found) = MathMarkdown.extract("Before\n\n$$ \(latex) $$\n\nAfter")
        #expect(found == [.init(latex: latex, isBlock: true, source: "$$ \(latex) $$")])
        #expect(text == "Before\n\n\(MathMarkdown.placeholder(0))\n\nAfter")
    }

    @Test func multilineBlockFormula() {
        #expect(formulas("$$\na_1 + b_2\n$$").map(\.latex) == ["a_1 + b_2"])
    }

    @Test func inlineFormula() {
        let (text, found) = MathMarkdown.extract("where $a_1 * b_2$ holds")
        #expect(found.map(\.latex) == ["a_1 * b_2"])
        #expect(found.map(\.isBlock) == [false])
        #expect(text == "where \(MathMarkdown.placeholder(0)) holds")
    }

    @Test func bracketDelimiters() {
        let found = formulas(#"Inline \(x^2\) and block \[\int_0^1 x\,dx\]"#)
        #expect(found.map(\.latex) == ["x^2", #"\int_0^1 x\,dx"#])
        #expect(found.map(\.isBlock) == [false, true])
    }

    @Test func currencyIsNotAFormula() {
        #expect(formulas("It costs $5 and $10.").isEmpty)
        #expect(formulas("Pay $ 5 or $ 6").isEmpty)
        #expect(formulas("From $x$1 to").isEmpty)
    }

    @Test func codeIsLeftAlone() {
        let markdown = "Run `echo $HOME $PATH` now\n\n```sh\necho $$ $a$\n```\n\n~~~\n$x$\n~~~"
        let (text, found) = MathMarkdown.extract(markdown)
        #expect(found.isEmpty)
        #expect(text == markdown)
    }

    @Test func formulaAfterCodeBlock() {
        #expect(formulas("```\n$a$\n```\nthen $b$").map(\.latex) == ["b"])
    }

    @Test func unclosedFormulaWhileStreaming() {
        let (text, found) = MathMarkdown.extract("Here: $$ \\frac{1}{2")
        #expect(found.isEmpty)
        #expect(text == "Here: $$ \\frac{1}{2")
    }

    @Test func alignBecomesAligned() {
        #expect(formulas(#"$$\begin{align*} a &= b \end{align*}$$"#).map(\.latex) == [#"\begin{aligned} a &= b \end{aligned}"#])
    }

    @Test func unsupportedCommandsAreRewritten() {
        let cases: [(String, String)] = [
            (#"0 < \operatorname{Re}(s) < 1"#, #"0 < \mathrm{Re}(s) < 1"#),
            (#"\operatorname*{arg\,max}_x"#, #"\mathrm{arg\,max}_x"#),
            (#"s = -2, -4, \dots"#, #"s = -2, -4, \ldots"#),
            (#"a + \dotsb + z"#, #"a + \cdots + z"#),
            (#"\left\lvert x \right\rvert"#, #"\left\vert x \right\vert"#),
            (#"\bigl( x \bigr)"#, #"( x )"#),
            (#"\boxed{x = 1}"#, #"{x = 1}"#),
            (#"x = 1 \tag{3}"#, #"x = 1"#),
            (#"\underset{n \to \infty}{\lim} a_n"#, #"{\lim}_{n \to \infty} a_n"#),
            (#"A \xrightarrow{f} B"#, #"A \rightarrow^{f} B"#),
            (#"\overset{\operatorname{def}}{=}"#, #"{=}^{\mathrm{def}}"#),
            (#"a \\ b \{ c \}"#, #"a \\ b \{ c \}"#),
        ]
        for (latex, expected) in cases {
            #expect(formulas("$$\(latex)$$").map(\.latex) == [expected], "\(latex)")
        }
    }

    /// Every formula in a recorded answer; several used to render as blank space.
    @Test func recordedFormulasRender() {
        let answer = #"""
        當 $\operatorname{Re}(s) > 1$ 時：
        $$
        \zeta(s) = \sum_{n=1}^{\infty} \frac{1}{n^s} = 1 + \frac{1}{2^s} + \frac{1}{3^s} + \cdots
        $$
        $$
        \zeta(s) = \prod_{p\ \text{為質數}} \frac{1}{1 - p^{-s}}
        $$
        $$
        \zeta(s) = 0,\ \ 0 < \operatorname{Re}(s) < 1 \quad \Longrightarrow \quad \operatorname{Re}(s) = \frac{1}{2}
        $$
        - **平凡零點**：$s = -2, -4, -6, \dots$（負偶數）。
        - 直線 $\operatorname{Re}(s) = \tfrac{1}{2}$ 上。
        $$
        \pi(x) = \operatorname{Li}(x) + O\!\left(\sqrt{x}\,\log x\right)
        $$
        其中 $\pi(x)$ 是不大於 $x$ 的質數個數，$\operatorname{Li}(x)$ 是對數積分函數。
        """#
        let found = formulas(answer)
        #expect(found.count == 10)
        for formula in found {
            #expect(MathMarkdown.canRender(formula), "\(formula.latex)")
        }
    }

    @Test func unparseableFormulaIsDetected() {
        #expect(!MathMarkdown.canRender(.init(latex: #"\nosuchcommand x"#, isBlock: false, source: "")))
    }

    @MainActor @Test func unparseableFormulaFallsBackToSource() throws {
        let output = try MathMarkdownParser().attributedString(for: #"See $\nosuchcommand x$ here"#)
        #expect(String(output.characters) == #"See $\nosuchcommand x$ here"#)
    }

    @Test func escapedDollarIsNotAFormula() {
        #expect(formulas(#"\$5 and \$6"#).isEmpty)
    }

    @MainActor @Test func parserRendersFormulasAsAttachments() throws {
        let output = try MathMarkdownParser().attributedString(for: "Euler: $e^{i\\pi} + 1 = 0$, costs $5 and $10")
        let text = String(output.characters)
        #expect(text == "Euler: \u{FFFC}, costs $5 and $10")
    }
}
