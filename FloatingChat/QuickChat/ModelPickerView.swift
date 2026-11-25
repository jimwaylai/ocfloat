import SwiftUI

/// The model menu, shown in place of the transcript. Arrow keys, Return and Esc reach it
/// through the panel's key monitor.
struct ModelPickerView: View {
    let model: QuickChatModel
    let picker: ModelPicker

    var body: some View {
        VStack(spacing: 0) {
            switch picker.level {
            case .models:
                ModelListView(model: model, picker: picker)
            case .variants(let info):
                VariantListView(model: model, picker: picker, info: info)
            }
        }
    }
}

private struct ModelListView: View {
    let model: QuickChatModel
    let picker: ModelPicker
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models", text: Binding(get: { picker.query }, set: model.setPickerQuery))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider() }

            let sections = picker.sections
            if sections.isEmpty {
                Text("No matching models")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PickerList(highlighted: picker.highlighted) {
                    let offsets = sectionOffsets(sections)
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        Text(verbatim: section.providerID)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, sectionIndex == 0 ? 2 : 10)
                            .padding(.bottom, 2)
                        ForEach(Array(section.models.enumerated()), id: \.element.id) { offset, info in
                            let index = offsets[sectionIndex] + offset
                            PickerRow(
                                index: index,
                                isHighlighted: index == picker.highlighted,
                                isCurrent: picker.current?.isSameModel(as: info.ref) == true,
                                action: { model.choosePickerRow(index) }
                            ) {
                                Text(info.name)
                                    .lineLimit(1)
                                Spacer()
                                if !info.variantIDs.isEmpty {
                                    if let variant = currentVariant(of: info) {
                                        Text(variant)
                                            .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { searchFocused = true }
    }

    private func sectionOffsets(_ sections: [ModelPicker.Section]) -> [Int] {
        var offsets: [Int] = []
        var total = 0
        for section in sections {
            offsets.append(total)
            total += section.models.count
        }
        return offsets
    }

    private func currentVariant(of info: ModelInfo) -> String? {
        guard let current = picker.current, current.isSameModel(as: info.ref) else { return nil }
        return current.variant
    }
}

private struct VariantListView: View {
    let model: QuickChatModel
    let picker: ModelPicker
    let info: ModelInfo

    var body: some View {
        VStack(spacing: 0) {
            Button(action: model.pickerBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(info.name)
                        .lineLimit(1)
                    Spacer()
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Back (Esc)")
            .overlay(alignment: .bottom) { Divider() }

            PickerList(highlighted: picker.highlighted) {
                ForEach(Array(picker.variantRows.enumerated()), id: \.offset) { index, variant in
                    PickerRow(
                        index: index,
                        isHighlighted: index == picker.highlighted,
                        isCurrent: isCurrent(variant),
                        action: { model.choosePickerRow(index) }
                    ) {
                        if let variant {
                            Text(verbatim: variant)
                        } else {
                            Text("Default")
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func isCurrent(_ variant: String?) -> Bool {
        guard let current = picker.current, current.isSameModel(as: info.ref) else { return false }
        return current.variant == variant
    }
}

/// Keeps the highlighted row scrolled into view as the arrow keys move it.
struct PickerList<Content: View>: View {
    let highlighted: Int
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(8)
            }
            .onAppear {
                // Centered, so the current model shows its neighbors and the first
                // section keeps its heading.
                proxy.scrollTo(highlighted, anchor: .center)
            }
            .onChange(of: highlighted) {
                proxy.scrollTo(highlighted)
            }
        }
    }
}

struct PickerRow<Label: View>: View {
    let index: Int
    let isHighlighted: Bool
    let isCurrent: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(isCurrent ? 1 : 0)
                label
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(.rect)
            .background(background, in: .rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        // Hover does not move the keyboard highlight: scrolling with the arrow keys would
        // slide rows under a resting pointer and make it jump.
        .onHover { hovered = $0 }
        .id(index)
    }

    private var background: Color {
        if isHighlighted { return Color.accentColor.opacity(0.2) }
        return hovered ? Color.primary.opacity(0.06) : .clear
    }
}
