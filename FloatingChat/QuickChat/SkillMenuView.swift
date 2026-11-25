import SwiftUI

/// The `/` menu, shown in place of the transcript. Arrow keys, Return, Tab and Esc reach it
/// through the panel's key monitor, while the input field keeps focus.
struct SkillMenuView: View {
    let model: QuickChatModel
    let menu: SkillMenu

    var body: some View {
        switch menu.state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            message("Couldn't load skills")
        case .loaded:
            let matches = menu.matches
            if matches.isEmpty {
                message("No matching skills")
            } else {
                PickerList(highlighted: menu.highlighted) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, skill in
                        PickerRow(
                            index: index,
                            isHighlighted: index == menu.highlighted,
                            isCurrent: false,
                            action: { model.chooseSkill(index) }
                        ) {
                            Text(verbatim: "/\(skill.name)")
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .layoutPriority(1)
                            if let description = skill.description, !description.isEmpty {
                                Text(verbatim: description)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Spacer(minLength: 0)
                        }
                        .help(skill.description ?? "")
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

/// A chosen skill, in the input bar (removable) or above a sent question.
struct SkillChip: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 11))
            Text(verbatim: name)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Remove Skill")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.15), in: .capsule)
    }
}
