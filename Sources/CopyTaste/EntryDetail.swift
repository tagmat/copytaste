import SwiftUI
import AppKit
import CopyTasteCore

struct EntryDetail: View {
    @ObservedObject var model: AppModel
    let entry: ClipEntry
    private var isCode: Bool { entry.text?.contains("{") == true && entry.text?.contains("}") == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(entry.kind.label, systemImage: entry.kind.symbol)
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button { model.togglePin(entry) } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).foregroundStyle(entry.isPinned ? Palette.accent : Palette.secondary)
                    .accessibilityLabel(entry.isPinned ? "Unpin clip" : "Pin clip").help(entry.isPinned ? "Unpin clip" : "Pin clip")
                Menu { EntryMenu(model: model, entry: entry) } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().padding(.leading, 12).accessibilityLabel("Clip actions")
            }.padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let imageData = entry.imageData, let image = NSImage(data: imageData) {
                        Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(entry.displayTitle)
                        Text(entry.displayTitle).font(.system(size: 28, weight: .medium, design: .serif))
                    } else if entry.kind == .link {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 36, weight: .light)).foregroundStyle(Palette.accent)
                        Text(entry.displayTitle).font(.system(size: 28, weight: .medium, design: .serif))
                        Text(entry.text ?? "").font(.system(size: 14)).foregroundStyle(Palette.accent).textSelection(.enabled)
                        Text("Link previews stay offline. No page content is fetched.")
                            .font(.system(size: 12)).lineSpacing(4).foregroundStyle(Palette.secondary)
                    } else {
                        Text(entry.text ?? "")
                            .font(isCode ? .system(size: 14, design: .monospaced) : .system(size: 25, weight: .regular, design: .serif))
                            .lineSpacing(isCode ? 7 : 10).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.horizontal, 32).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "app").foregroundStyle(Palette.secondary)
                    Text(entry.sourceName)
                    Spacer()
                    Text(entry.createdAt, format: .dateTime.hour().minute()).foregroundStyle(Palette.secondary)
                }.font(.system(size: 11))
                HStack {
                    Text(entry.kind == .image ? ByteCountFormatter.string(fromByteCount: Int64(entry.byteCount), countStyle: .file) : "\(entry.text?.count ?? 0) characters")
                    Spacer()
                    if entry.isPinned { Label("Pinned", systemImage: "pin.fill") }
                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Divider().overlay(Palette.divider)
                HStack {
                    Menu {
                        Button("No collection") { model.move(entry, to: nil) }
                        ForEach(model.snapshot.collections) { collection in
                            Button(collection.name) { model.move(entry, to: collection.id) }
                        }
                    } label: {
                        Label(model.snapshot.collections.first { $0.id == entry.collectionID }?.name ?? "Add to collection", systemImage: "folder.badge.plus")
                            .font(.system(size: 11))
                    }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                    Button { model.copy(entry) } label: { Label("Copy", systemImage: "square.on.square") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .help("Copy selected clip (⌘Return)")
                }
            }.padding(30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
    }
}

struct EntryMenu: View {
    @ObservedObject var model: AppModel
    let entry: ClipEntry
    var body: some View {
        Button("Copy") { model.copy(entry) }
        Button(entry.isPinned ? "Unpin" : "Pin") { model.togglePin(entry) }
        Menu("Move to Collection") {
            Button("None") { model.move(entry, to: nil) }
            ForEach(model.snapshot.collections) { collection in
                Button(collection.name) { model.move(entry, to: collection.id) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(entry) }
    }
}
