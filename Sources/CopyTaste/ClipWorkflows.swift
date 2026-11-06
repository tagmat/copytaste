import CopyTasteCore
import SwiftUI

struct ClipDraft {
    let id: UUID?
    var title: String
    var text: String?

    init(_ entry: ClipEntry? = nil) {
        id = entry?.id
        title = entry?.title ?? ""
        text = entry == nil ? "" : entry?.text
    }
}

struct ClipEditor: View {
    private enum Field: Hashable { case title, body }

    @Binding var draft: ClipDraft
    let onSave: () -> String?
    let onClose: () -> Void
    @State private var error: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.id == nil ? "New snippet" : "Edit clip")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            TextField("Title (optional)", text: $draft.title).textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .title)
            if draft.text != nil {
                TextEditor(text: Binding(get: { draft.text ?? "" }, set: { draft.text = $0 }))
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(7).frame(height: 150)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Clip text")
                    .focused($focusedField, equals: .body)
            }
            Text("Snippets start pinned. Retention still applies unless Keep pins past expiry is enabled.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.violet) }
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button("Save Clip") { error = onSave() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 440).modifier(FrostedSurface(radius: 18))
        .task {
            await Task.yield()
            focusedField = draft.text == nil ? .title : .body
        }
    }
}

enum BatchSeparator: String, CaseIterable, Identifiable {
    case lines = "New line", paragraphs = "Blank line", tabs = "Tab"
    var id: Self { self }
    var value: String {
        switch self {
        case .lines: "\n"
        case .paragraphs: "\n\n"
        case .tabs: "\t"
        }
    }
}

enum ClipBatch {
    static let limit = 12

    static func text(_ entries: [ClipEntry], separator: BatchSeparator) -> String? {
        guard (1...limit).contains(entries.count) else { return nil }
        let pieces = entries.compactMap { entry in
            entry.kind == .text || entry.kind == .link ? entry.text : nil
        }
        guard pieces.count == entries.count else { return nil }
        let text = pieces.joined(separator: separator.value)
        return text.utf8.count <= CapturePolicy.maxTextBytes ? text : nil
    }
}

struct BatchPreview: View {
    let entries: [ClipEntry]
    @Binding var separator: BatchSeparator
    let canPaste: Bool
    let automaticPaste: Bool
    let onRemove: (UUID) -> Void
    let onClear: () -> Void
    let onClose: () -> Void
    let onDeliver: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Paste batch").font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                Button("Clear", action: onClear).disabled(entries.isEmpty)
            }
            if entries.isEmpty {
                Text("Use ⌘B on a text or link card to add it here.")
                    .foregroundStyle(Palette.secondary).font(.system(size: 12))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            HStack {
                                Text("\(offset + 1)").monospacedDigit().foregroundStyle(Palette.mint)
                                Text(String(entry.displayTitle.prefix(120))).lineLimit(1)
                                Spacer()
                                Button { onRemove(entry.id) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.plain).accessibilityLabel("Remove item \(offset + 1)")
                            }.font(.system(size: 12)).padding(8)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }.frame(height: min(CGFloat(entries.count) * 34, 178))
            }
            Picker("Separate with", selection: $separator) {
                ForEach(BatchSeparator.allCases) { Text($0.rawValue).tag($0) }
            }
            if !entries.isEmpty && !canPaste {
                Text("The batch exceeds 512 KB. Remove an item to continue.")
                    .font(.system(size: 11)).foregroundStyle(Palette.violet)
            }
            HStack {
                Button("Back", action: onClose)
                Spacer()
                if automaticPaste { Button("Copy") { onDeliver(true) }.disabled(!canPaste) }
                Button(automaticPaste ? "Paste" : "Copy") { onDeliver(!automaticPaste) }
                    .buttonStyle(.borderedProminent).disabled(!canPaste)
            }
        }
        .padding(22).frame(width: 440).modifier(FrostedSurface(radius: 18))
    }
}
