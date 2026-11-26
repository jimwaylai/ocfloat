import SwiftUI

struct QuickChatView: View {
    @Bindable var model: QuickChatModel
    @FocusState private var inputFocused: Bool
    @AppStorage(PanelOpacity.activeKey) private var activeOpacity = PanelOpacity.defaultActive
    @AppStorage(PanelOpacity.idleKey) private var idleOpacity = PanelOpacity.defaultIdle

    var body: some View {
        VStack(spacing: 0) {
            if model.isExpanded {
                header
            }
            if let picker = model.picker {
                ModelPickerView(model: model, picker: picker)
                    .frame(maxHeight: .infinity)
            } else if let recents = model.recents {
                RecentConversationsView(model: model, recents: recents)
                    .frame(maxHeight: .infinity)
            } else if let skillMenu = model.skillMenu {
                SkillMenuView(model: model, menu: skillMenu)
                    .frame(maxHeight: .infinity)
            } else if model.isExpanded {
                TranscriptView(model: model) { model.transcriptHeight = $0 }
                    .frame(maxHeight: .infinity)
            }
            VStack(spacing: 0) {
                ConnectionNotice(connection: model.connection)
                if model.previousConversation != nil {
                    resetNotice
                }
                inputBar
            }
            .overlay(alignment: .top) {
                if model.isExpanded || model.picker != nil || model.recents != nil || model.skillMenu != nil { Divider() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.inputBarHeight = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(PanelOpacity.clamped(model.isPanelActive ? activeOpacity : idleOpacity))
                .animation(.easeOut(duration: 0.2), value: model.isPanelActive)
                .ignoresSafeArea()
        }
        .overlay {
            if model.isDropTargeted { DropHighlight() }
        }
        .onAppear { inputFocused = true }
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    private var header: some View {
        Text(model.conversation.title ?? "")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 60)
            .frame(maxWidth: .infinity)
            .frame(height: QuickChatLayout.headerHeight)
            .overlay(alignment: .leading) {
                headerButton("xmark", help: "Close (⌘W)", action: model.close)
                    .padding(.leading, 10)
            }
            .overlay(alignment: .trailing) {
                HStack(spacing: 2) {
                    headerButton("clock.arrow.circlepath", help: "Recent Conversations (⌘K)", isOn: model.recents != nil, action: model.toggleRecents)
                    headerButton("square.and.pencil", help: "New Conversation (⌘N)", action: model.newConversation)
                }
                .padding(.trailing, 10)
            }
            .overlay(alignment: .bottom) { Divider() }
    }

    private func headerButton(_ symbol: String, help: LocalizedStringKey, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isOn ? .primary : .secondary)
        .help(help)
    }

    private var resetNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("Started a new conversation")
                .foregroundStyle(.secondary)
            Text(verbatim: "·")
                .foregroundStyle(.tertiary)
            Button("Back to previous") {
                model.returnToPreviousConversation()
            }
            .buttonStyle(.link)
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .transition(.opacity)
    }

    /// The question on the first line, full width; under it the attach button and model
    /// menu on the left and send / stop on the right.
    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.attachments.isEmpty {
                ScrollView(.horizontal) {
                    AttachmentStrip(attachments: model.attachments, onRemove: model.removeAttachment)
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                }
                .scrollIndicators(.never)
            }
            if model.hasUnsupportedImages {
                Label("The current model can't read images. Choose another model to send.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let skill = model.selectedSkill {
                    SkillChip(name: skill.name, onRemove: model.removeSelectedSkill)
                }
                TextField("Ask anything…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .lineLimit(1...8)
                    .focused($inputFocused)
            }
            .padding(.horizontal, 4)
            HStack(spacing: 12) {
                Button(action: model.chooseFiles) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(.circle)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Attach Files")
                if let label = model.currentModelLabel {
                    modelButton(label)
                }
                Spacer(minLength: 0)
                sendOrStopButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Send while idle (dimmed when there is nothing to send), stop while answering.
    private var sendOrStopButton: some View {
        let isAnswering = model.conversation.isAnswering
        let enabled = isAnswering || model.canSubmit
        return Button {
            if isAnswering { model.stop() } else { model.submit() }
        } label: {
            Image(systemName: isAnswering ? "stop.fill" : "arrow.up")
                .font(.system(size: isAnswering ? 11 : 14, weight: .bold))
                .foregroundStyle(enabled ? Color(nsColor: .windowBackgroundColor) : Color.secondary)
                .frame(width: 30, height: 30)
                .background(enabled ? Color.primary : Color.primary.opacity(0.1), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(isAnswering ? "Stop (⌘.)" : "Send (Return)")
    }

    private func modelButton(_ label: String) -> some View {
        Button(action: model.toggleModelPicker) {
            HStack(spacing: 4) {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(model.picker == nil ? .secondary : .primary)
        .help("Choose Model")
    }
}

private struct ConnectionNotice: View {
    let connection: ConnectionManager

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                Spacer()
                switch connection.state {
                case .serviceNotRunning:
                    Button("Start") { connection.startService() }
                case .opencodeNotFound:
                    Button("Check Again") { connection.retryNow() }
                case .connected, .connecting, .invalidServerURL:
                    EmptyView()
                }
            }
            .font(.system(size: 12))
            .controlSize(.small)
            .padding(.horizontal, 18)
            .padding(.top, 10)
        }
    }

    private var message: LocalizedStringKey? {
        switch connection.state {
        case .connected: nil
        case .connecting: "Connecting to opencode…"
        case .serviceNotRunning: "opencode service is not running"
        case .opencodeNotFound: "opencode is not installed"
        case .invalidServerURL: "The server URL in Settings is not valid"
        }
    }
}
