import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A wrapping row of attachments, removable while they are still in the Draft.
struct AttachmentStrip: View {
    let attachments: [Attachment]
    var size: CGFloat = 44
    var onRemove: ((Attachment.ID) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentChip(attachment: attachment, size: size, onRemove: onRemove.map { remove in { remove(attachment.id) } })
            }
        }
    }
}

private struct AttachmentChip: View {
    let attachment: Attachment
    let size: CGFloat
    let onRemove: (() -> Void)?
    @State private var hovered = false

    var body: some View {
        content
            .help(attachment.name)
            .overlay(alignment: .topTrailing) {
                if let onRemove, hovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help("Remove")
                }
            }
            .onHover { hovered = $0 }
    }

    @ViewBuilder private var content: some View {
        if let data = attachment.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
        } else {
            HStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(for: UTType(mimeType: attachment.mime) ?? .data))
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(attachment.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 200)
            .frame(height: min(size, 44))
            .background(.quaternary, in: .rect(cornerRadius: 8))
        }
    }
}

/// Shown over the whole panel while files or images are dragged over it.
struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 10))
            .overlay {
                Label("Drop to attach", systemImage: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(4)
            .allowsHitTesting(false)
    }
}
