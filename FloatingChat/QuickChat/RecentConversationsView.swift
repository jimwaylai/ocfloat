import SwiftUI

/// The ⌘K menu, shown in place of the transcript. Arrow keys, Return and Esc reach it
/// through the panel's key monitor, while the input field keeps focus.
struct RecentConversationsView: View {
    let model: QuickChatModel
    let recents: RecentConversations

    var body: some View {
        VStack(spacing: 0) {
            Text("Recent Conversations")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Divider() }

            switch recents.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                message("Couldn't load conversations")
            case .loaded(let sessions) where sessions.isEmpty:
                message("No conversations yet")
            case .loaded(let sessions):
                PickerList(highlighted: recents.highlighted) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        PickerRow(
                            index: index,
                            isHighlighted: index == recents.highlighted,
                            isCurrent: session.id == recents.currentID,
                            action: { model.chooseRecent(index) }
                        ) {
                            if let title = session.title, !title.isEmpty {
                                Text(verbatim: title)
                                    .lineLimit(1)
                            } else {
                                Text("Untitled")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Date(timeIntervalSince1970: session.time.updated / 1000), format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
