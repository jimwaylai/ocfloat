import AppKit
import SwiftUI
import Textual

struct AnswerView: View {
    let answer: Answer
    let modelName: String?
    /// Only the last answer can be regenerated.
    let onRegenerate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(answer.parts) { part in
                switch part {
                case .text(_, let text) where !text.isEmpty:
                    MarkdownText(text)
                case .reasoning(let reasoning):
                    ReasoningView(reasoning: reasoning, isThinking: answer.isActive && reasoning.ended == nil)
                case .tool(let call):
                    ToolCallView(call: call)
                default:
                    EmptyView()
                }
            }
            if answer.isActive, !showsOwnProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Thinking…")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            switch answer.status {
            case .failed(let message):
                Label(message.isEmpty ? String(localized: "Something went wrong.") : message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            case .interrupted:
                Text("Stopped")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .waiting, .running, .succeeded:
                EmptyView()
            }
            if !answer.isActive {
                AnswerFooter(text: answer.text, modelName: modelName, onRegenerate: onRegenerate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Streaming text, running tools and live reasoning already show that work is happening.
    private var showsOwnProgress: Bool {
        switch answer.parts.last {
        case .text: true
        case .tool(let call): call.state == .running
        case .reasoning(let reasoning): reasoning.ended == nil
        case nil: false
        }
    }
}

private struct MarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        StructuredText(markdown, parser: MathMarkdownParser())
            .font(.system(size: 14))
            // The innermost environment value wins, so the override must come before the preset.
            .textual.codeBlockStyle(CopyableCodeBlockStyle())
            .textual.tableStyle(SubtleTableStyle())
            .textual.inlineStyle(Self.inlineStyle)
            .textual.structuredTextStyle(.gitHub)
            .textual.textSelection(.enabled)
    }

    /// GitHub's inline style, but with Slack-like inline code: GitHub's near-white code
    /// background reads as a white block on the translucent panel.
    private static let inlineStyle = InlineStyle()
        .code(
            .monospaced,
            .fontScale(0.85),
            .backgroundColor(DynamicColor(light: .black.opacity(0.06), dark: .white.opacity(0.1))),
            .foregroundColor(DynamicColor(
                light: Color(red: 224 / 255, green: 30 / 255, blue: 90 / 255),
                dark: Color(red: 232 / 255, green: 145 / 255, blue: 45 / 255)
            ))
        )
        .strong(.fontWeight(.semibold))
        .link(.foregroundColor(DynamicColor(
            light: Color(red: 44 / 255, green: 101 / 255, blue: 207 / 255),
            dark: Color(red: 76 / 255, green: 142 / 255, blue: 248 / 255)
        )))
}

/// GitHub's table style, but GitHub's near-white striping reads as white rows on the
/// translucent panel, so even rows are only a little lighter than odd ones.
private struct SubtleTableStyle: StructuredText.TableStyle {
    private static let borderWidth: CGFloat = 1
    private static let stripe = DynamicColor(light: .white.opacity(0.35), dark: .white.opacity(0.05))
    private static let border = DynamicColor(
        light: Color(red: 228 / 255, green: 228 / 255, blue: 232 / 255),
        dark: Color(red: 66 / 255, green: 68 / 255, blue: 78 / 255)
    )

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: Self.borderWidth, vertical: Self.borderWidth)
            .textual.blockSpacing(.init(top: 0, bottom: 16))
            .textual.tableBackground { layout in
                Canvas { context, _ in
                    for row in layout.rowIndices.dropFirst() where row.isMultiple(of: 2) {
                        context.fill(Path(layout.rowBounds(row).integral), with: .style(Self.stripe))
                    }
                }
            }
            .textual.tableOverlay { layout in
                Canvas { context, _ in
                    for divider in layout.dividers() {
                        context.fill(Path(divider), with: .style(Self.border))
                    }
                }
            }
            .padding(Self.borderWidth)
            .border(Self.border, width: Self.borderWidth)
    }
}

private struct CopyableCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        CodeBlockView(configuration: configuration)
    }
}

private struct CodeBlockView: View {
    let configuration: StructuredText.CodeBlockStyleConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Textual's selection overlay swallows clicks everywhere except inside `Overflow`
            // regions, and disabling selection keeps it from adding its own overlay there.
            Overflow { state in
                HStack {
                    Text(configuration.languageHint ?? "")
                        .foregroundStyle(.secondary)
                    Spacer()
                    CopyButton(title: "Copy") { configuration.codeBlock.copyToPasteboard() }
                        .background(PointingHandCursor())
                }
                .font(.system(size: 11))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(minWidth: state.containerWidth ?? 0)
            }
            .textual.textSelection(.disabled)
            .scrollDisabled(true)
            .background(Color.primary.opacity(0.04))
            Overflow {
                configuration.label
                    .textual.lineSpacing(.fontScaled(0.225))
                    .textual.fontScale(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospaced()
                    .padding(12)
            }
        }
        .background(Color.primary.opacity(0.05))
        .clipShape(.rect(cornerRadius: 8))
        .textual.blockSpacing(.init(top: 0, bottom: 16))
    }
}

/// Textual's selection overlay covers the code block and sets the I-beam on every mouse move,
/// hiding SwiftUI hover handlers below it. A tracking area receives moves regardless of
/// what lies on top, so the pointing hand is set right after Textual's cursor.
private struct PointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { setCursor() }
        override func mouseMoved(with event: NSEvent) { setCursor() }
        override func cursorUpdate(with event: NSEvent) { setCursor() }

        private func setCursor() {
            NSCursor.pointingHand.set()
            DispatchQueue.main.async { NSCursor.pointingHand.set() }
        }
    }
}

/// Shows a checkmark for a moment after copying.
private struct CopyButton: View {
    let title: LocalizedStringKey?
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        Button {
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            if let title {
                Label(copied ? "Copied" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
            } else {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct ReasoningView: View {
    let reasoning: Answer.Reasoning
    let isThinking: Bool
    @State private var expanded = false

    var body: some View {
        Disclosure(expanded: $expanded, canExpand: !reasoning.text.isEmpty) {
            HStack(spacing: 6) {
                if isThinking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "brain")
                }
                Text(title)
            }
        } content: {
            Text(reasoning.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var title: String {
        if isThinking { return String(localized: "Thinking…") }
        guard let duration = reasoning.duration else { return String(localized: "Thought") }
        return String(localized: "Thought for \(max(Int(duration.rounded()), 1))s")
    }
}

private struct ToolCallView: View {
    let call: Answer.ToolCall
    @State private var expanded = false

    var body: some View {
        Disclosure(expanded: $expanded, canExpand: call.output?.isEmpty == false) {
            HStack(spacing: 6) {
                if call.state == .running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon)
                }
                Text(description)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(call.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        } content: {
            ScrollView {
                Text(call.output ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
    }

    private var icon: String {
        switch call.name {
        case "websearch": "magnifyingglass"
        case "webfetch": "globe"
        default: "wrench.and.screwdriver"
        }
    }

    private var description: String {
        let subject = call.subject ?? ""
        return switch call.name {
        case "websearch": String(localized: "Searching: \(subject)")
        case "webfetch": String(localized: "Reading: \(subject)")
        default: String(localized: "Using \(call.name)")
        }
    }
}

/// A one-line summary that expands to show details, indented under a guide line.
private struct Disclosure<Label: View, Content: View>: View {
    @Binding var expanded: Bool
    let canExpand: Bool
    @ViewBuilder let label: Label
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    label
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canExpand)
            if expanded, canExpand {
                content
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.quaternary).frame(width: 2)
                    }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

private struct AnswerFooter: View {
    let text: String
    let modelName: String?
    let onRegenerate: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if !text.isEmpty {
                CopyButton(title: nil) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .help("Copy Answer")
            }
            if let onRegenerate {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Regenerate")
            }
            if let modelName {
                Text(modelName)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }
}
