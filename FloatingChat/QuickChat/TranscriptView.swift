import SwiftUI

struct TranscriptView: View {
    let model: QuickChatModel
    let onHeightChange: (CGFloat) -> Void

    private var conversation: ConversationController { model.conversation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(conversation.turns) { turn in
                    TurnView(turn: turn, modelName: modelName(for: turn), onRegenerate: regenerateAction(for: turn))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
    }

    private func modelName(for turn: Turn) -> String? {
        guard let ref = turn.answer.model else { return nil }
        return model.models.displayName(for: ref)
    }

    private func regenerateAction(for turn: Turn) -> (() -> Void)? {
        guard turn.id == conversation.turns.last?.id, conversation.canRegenerate else { return nil }
        let model = model
        return { model.regenerate() }
    }
}

private struct TurnView: View {
    let turn: Turn
    let modelName: String?
    let onRegenerate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .trailing, spacing: 6) {
                if let skill = turn.skill {
                    SkillChip(name: skill)
                }
                if !turn.attachments.isEmpty {
                    AttachmentStrip(attachments: turn.attachments, size: 96)
                }
                if !turn.question.isEmpty {
                    Text(turn.question)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary, in: .rect(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 60)
            AnswerView(answer: turn.answer, modelName: modelName, onRegenerate: onRegenerate)
        }
    }
}
