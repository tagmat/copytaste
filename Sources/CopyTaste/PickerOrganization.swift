import CopyTasteCore
import SwiftUI

enum FolderScope: Equatable {
    case all, unfiled, folder(UUID)

    func includes(_ clip: ClipEntry) -> Bool {
        switch self {
        case .all: true
        case .unfiled: clip.collectionID == nil
        case .folder(let id): clip.collectionID == id
        }
    }
}

struct FolderDraft {
    var name = ""
    var folderID: UUID?
    var clipID: UUID?
}

struct FolderEditor: View {
    @Binding var draft: FolderDraft
    let onSave: () -> String?
    let onClose: () -> Void
    @State private var issue: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(draft.folderID == nil ? "New folder" : "Rename folder", systemImage: "folder")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
            TextField("Folder name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            if draft.clipID != nil {
                Text("The selected clip will move into this folder.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            if let issue { Text(issue).font(.system(size: 11)).foregroundStyle(Palette.violet) }
            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                Button(draft.folderID == nil ? "Create Folder" : "Save Name", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22).frame(width: 400).modifier(FrostedSurface(radius: 18))
        .task { await Task.yield(); nameFocused = true }
    }

    private func save() { issue = onSave() }
}

struct ColorSwatch: View {
    let color: HexColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if color.alpha < 255 {
                    Canvas { context, size in
                        let tile = 10.0
                        for row in 0..<Int(ceil(size.height / tile)) {
                            for column in 0..<Int(ceil(size.width / tile)) {
                                let rect = CGRect(x: Double(column) * tile, y: Double(row) * tile,
                                    width: tile, height: tile)
                                context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2) ? Palette.secondary : Palette.raised))
                            }
                        }
                    }
                }
                Color(red: Double(color.red) / 255, green: Double(color.green) / 255,
                    blue: Double(color.blue) / 255, opacity: Double(color.alpha) / 255)
            }
            .frame(height: 118)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.15)))
            .accessibilityHidden(true)
            Text(color.hex).font(.system(size: 18, weight: .medium, design: .monospaced))
            Text(color.cssRGB).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }
}
