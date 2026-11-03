import SwiftUI
import AppKit
import CopyTasteCore

enum Palette {
    static let rail = Color(red: 36/255, green: 61/255, blue: 52/255)
    static let railSecondary = Color(red: 199/255, green: 211/255, blue: 201/255)
    static let canvas = Color(red: 247/255, green: 246/255, blue: 240/255)
    static let paper = Color(red: 254/255, green: 253/255, blue: 249/255)
    static let ink = Color(red: 36/255, green: 45/255, blue: 40/255)
    static let secondary = Color(red: 98/255, green: 106/255, blue: 97/255)
    static let accent = Color(red: 166/255, green: 68/255, blue: 47/255)
    static let selection = Color(red: 229/255, green: 235/255, blue: 221/255)
    static let divider = Color(red: 224/255, green: 226/255, blue: 216/255)
}

struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(Color(red: 0.88, green: 0.76, blue: 0.51))
            Image(systemName: "square.on.square")
                .font(.system(size: size * 0.48, weight: .semibold)).foregroundStyle(Palette.rail)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var showClearConfirmation = false
    @State private var addingCollection = false
    @State private var collectionName = ""
    @State private var syncPassphrase = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                Rectangle().fill(Palette.divider).frame(height: 1)
                if model.isLocked { lockedState }
                else if model.showSettings { SettingsView(model: model) }
                else if model.snapshot.entries.isEmpty { welcomeState }
                else {
                    HStack(spacing: 0) {
                        historyList.frame(width: 330)
                        Rectangle().fill(Palette.divider).frame(width: 1)
                        if let entry = model.selectedEntry, model.visibleEntries.contains(where: { $0.id == entry.id }) {
                            EntryDetail(model: model, entry: entry)
                        } else { noSelection }
                    }
                }
                footer
            }.background(Palette.canvas)
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Palette.rail, in: Capsule()).foregroundStyle(.white)
                    .padding(.bottom, 52).allowsHitTesting(false).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert("CopyTaste", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Clear all history?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: { Text("All entries, including pinned items, will be removed. Your collections will stay. A clipboard item copied by CopyTaste will also be cleared if it is still current.") }
        .alert("New collection", isPresented: $addingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) { }
            Button("Create") { model.createCollection(collectionName); collectionName = ""; model.showSettings = false }
        } message: { Text("Keep related clips together. Up to 30 collections, with names of up to 40 characters.") }
        .onChange(of: model.scope) { _, _ in model.selectedID = model.visibleEntries.first?.id }
        .onChange(of: model.query) { _, _ in
            if !model.visibleEntries.contains(where: { $0.id == model.selectedID }) { model.selectedID = model.visibleEntries.first?.id }
        }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text("CopyTaste").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("by tagmat").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.railSecondary)
                }
            }.padding(.top, 48).padding(.bottom, 34).padding(.horizontal, 22)
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                navRow("Clipboard", icon: "square.on.square", scope: .all, count: model.snapshot.entries.count)
                navRow("Pinned", icon: "pin", scope: .pinned, count: model.snapshot.entries.filter(\.isPinned).count)
                Divider().overlay(Palette.railSecondary.opacity(0.2)).padding(.vertical, 14)
                navRow("Text", icon: "text.alignleft", scope: .kind(.text))
                navRow("Links", icon: "link", scope: .kind(.link))
                navRow("Images", icon: "photo", scope: .kind(.image))
            }.padding(.horizontal, 12)
            HStack {
                Text("Collections").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.railSecondary)
                Spacer()
                Button { addingCollection = true } label: { Image(systemName: "plus").font(.system(size: 12)) }
                    .buttonStyle(.plain).help("New collection").accessibilityLabel("New collection")
                    .disabled(model.isLocked)
            }.padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 10)
            Group {
                VStack(spacing: 4) {
                    ForEach(model.snapshot.collections) { collection in
                        navRow(collection.name, icon: "folder", scope: .collection(collection.id))
                            .contextMenu {
                                Button("Delete Collection", role: .destructive) { model.deleteCollection(collection.id) }
                            }
                    }
                    if model.snapshot.collections.isEmpty {
                        Text("A place for related clips.")
                            .font(.system(size: 11)).foregroundStyle(Palette.railSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 4)
                    }
                }.padding(.horizontal, 12)
            }
            }
            }.padding(.bottom, 20)
            Button { model.showSettings = true } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: model.preferences.storageMode == .memory ? "memorychip" : "lock.shield")
                        .font(.system(size: 19)).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.preferences.storageMode == .memory ? "Here for now." : "Yours to keep.")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.preferences.storageMode == .memory ? "History lives in memory.\nGone when you quit or lock." : "Encrypted history.\nOnly on your chosen storage.")
                            .font(.system(size: 11)).lineSpacing(3).foregroundStyle(Palette.railSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 14)
            HStack(spacing: 18) {
                Button { model.showSettings.toggle() } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.plain).font(.system(size: 12)).help("Settings (⌘,)")
                Spacer()
                Button { model.lock() } label: { Image(systemName: "lock") }
                    .buttonStyle(.plain).accessibilityLabel("Lock history").help("Lock history (⇧⌘L)")
                    .disabled(model.isDemo || model.isLocked)
            }.foregroundStyle(Palette.railSecondary).padding(.horizontal, 24).padding(.bottom, 20)
        }.frame(width: 210).background(Palette.rail).foregroundStyle(.white)
    }

    private func navRow(_ name: String, icon: String, scope: HistoryScope, count: Int? = nil) -> some View {
        let selected = model.scope == scope && !model.showSettings
        return Button { model.scope = scope; model.showSettings = false } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20)
                Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.system(size: 11)).monospacedDigit().opacity(0.8) }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .background(selected ? Color.white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(model.showSettings ? "Settings" : model.scopeTitle)
                .font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                .lineLimit(1)
            Spacer()
            if !model.isLocked && !model.showSettings {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                    TextField("Search your clips", text: $model.query).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search your clips")
                    Text("⌘F").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.font(.system(size: 12)).padding(10).frame(width: 240)
                    .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.divider, lineWidth: 1))
            }
            Button { model.toggleCapture() } label: {
                HStack(spacing: 6) {
                    Image(systemName: model.isCapturing ? "pause.circle" : "play.circle")
                    Text(model.isDemo ? "Demo" : (model.isCapturing ? "Capturing" : "Paused"))
                }.font(.system(size: 12, weight: .medium))
            }.buttonStyle(.bordered).controlSize(.regular)
                .disabled(model.isLocked || model.isDemo).help("Pause or resume clipboard capture (⇧⌘P)")
            Menu {
                Button("Clear History…", role: .destructive) { showClearConfirmation = true }
                    .disabled(model.isLocked || model.snapshot.entries.isEmpty)
                Button("Settings…") { model.showSettings = true }
                Divider()
                Button("Quit CopyTaste") { NSApp.terminate(nil) }
            } label: { Image(systemName: "ellipsis").frame(width: 20) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions")
        }.padding(.horizontal, 26).padding(.top, 38).padding(.bottom, 22)
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.query.isEmpty ? "Recent clips" : "Search results").font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(model.visibleEntries.count) items").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)
            if model.visibleEntries.isEmpty {
                ContentUnavailableView.search(text: model.query).frame(maxHeight: .infinity)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleEntries) { entry in
                        HistoryRow(entry: entry, selected: entry.id == model.selectedID)
                            .tag(entry.id).listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowBackground(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedID = entry.id }
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.copy(entry) })
                            .accessibilityAction { model.selectedID = entry.id }
                            .contextMenu { EntryMenu(model: model, entry: entry) }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.background(Palette.canvas)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: model.isLocked ? "lock.fill" : "shield.lefthalf.filled")
            Text(model.isLocked ? "History locked" : model.storageLabel)
            if model.isDemo { Text("· Sample content · capture disabled") }
            Spacer()
            if !model.isLocked {
                Text("\(model.preferences.retentionDays)d retention").padding(.trailing, 14)
            }
            Text("Open anywhere").foregroundStyle(Palette.secondary)
            Text("⇧ ⌘ V").fontWeight(.medium)
        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 24).frame(height: 36)
            .background(Palette.paper).overlay(alignment: .top) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }

    private var lockedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield").font(.system(size: 40, weight: .light)).foregroundStyle(Palette.rail)
            Text("A little privacy, please.").font(.system(size: 30, weight: .medium, design: .serif))
            Text(model.preferences.storageMode == .memory ? "Memory history was cleared when you locked.\nOpen a fresh session whenever you're ready." : "Your saved history is encrypted.\nAuthenticate with your Mac to open it.")
                .font(.system(size: 13)).lineSpacing(5).multilineTextAlignment(.center).foregroundStyle(Palette.secondary)
            if model.preferences.storageMode == .iCloud {
                SecureField("iCloud sync passphrase", text: $syncPassphrase).textFieldStyle(.roundedBorder).frame(width: 280)
            }
            Button(model.isAuthenticating ? "Authenticating…" : "Open History") {
                let phrase = syncPassphrase
                syncPassphrase = ""
                Task { await model.unlock(syncPassphrase: phrase) }
            }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isAuthenticating)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }

    private var welcomeState: some View {
        VStack(alignment: .leading, spacing: 22) {
            BrandMark(size: 54)
            Text("Keep the good bits.\nLet the rest go.")
                .font(.system(size: 44, weight: .medium, design: .serif)).tracking(-1)
            Text("Your text, links and images, ready for another taste.\nHistory stays in memory unless you choose to save it.")
                .font(.system(size: 14)).lineSpacing(6).foregroundStyle(Palette.secondary)
            HStack(spacing: 14) {
                Button(model.isCapturing ? "Waiting for your next copy…" : "Start Capturing") { model.toggleCapture() }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isCapturing || model.isDemo)
                Button("Privacy & storage") { model.showSettings = true }.buttonStyle(.link)
            }
            Label("Private clipboard markers and protected apps are always excluded.", systemImage: "shield.lefthalf.filled")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).padding(40)
    }

    private var noSelection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 28, weight: .light))
            Text("A second look starts here.").font(.system(size: 22, design: .serif))
            Text("Select a clip to preview or copy it.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
    }
}

struct HistoryRow: View {
    let entry: ClipEntry
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.kind.symbol).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(entry.sourceName).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Palette.accent) }
                Text(entry.createdAt, style: .relative).font(.system(size: 9)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Text(entry.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let text = entry.text {
                Text(text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(2)
            } else if let data = entry.imageData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill().frame(height: 42).clipped().clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.selection : Palette.paper, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }
}

extension ClipKind {
    var symbol: String {
        switch self { case .text: "text.alignleft"; case .link: "link"; case .image: "photo" }
    }
    var label: String {
        switch self { case .text: "Text"; case .link: "Link"; case .image: "Image" }
    }
}
