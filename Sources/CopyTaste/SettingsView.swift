import SwiftUI
import ServiceManagement
import CopyTasteCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onShowPicker: () -> Void = {}
    var onShortcutChange: @MainActor @Sendable (SelectorShortcut) -> Void = { _ in }
    @State private var storage = StorageMode.memory
    @State private var pinnedOnly = false
    @State private var syncPassphrase = ""
    @State private var newFolder = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 12) {
                    BrandMark(size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A few things, your way.").font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("CopyTaste · advanced settings").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                if model.isLocked {
                    Label("Unlock history before changing storage or folders.", systemImage: "lock.shield")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Button("Open Selector", action: onShowPicker)
                }
                section("Storage & sync", symbol: "externaldrive") {
                    Picker("Keep history in", selection: $storage) {
                        Text("Memory only · default").tag(StorageMode.memory)
                        Text("Encrypted on this Mac").tag(StorageMode.encryptedLocal)
                        Text("Encrypted in a folder").tag(StorageMode.encryptedFolder)
                        Text("iCloud Drive · encrypted sync").tag(StorageMode.iCloud)
                    }
                    Text(storage == .memory ? "History lives in memory and is released on lock or quit. File paste creates a private temporary transfer file for up to five minutes; lock and quit remove it sooner." : "History is encrypted before it is written. Pinned items still obey retention limits.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    if storage == .iCloud {
                        SecureField("Sync passphrase · 16+ characters", text: $syncPassphrase).textFieldStyle(.roundedBorder)
                        Text("Use the same phrase on every Mac. It is never saved and cannot be recovered. Leaving sync keeps the shared encrypted file in iCloud.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        if model.preferences.storageMode == .iCloud && !model.isLocked {
                            HStack {
                                if let date = model.lastSyncAt {
                                    Text("Last local merge: \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(Palette.secondary)
                                }
                                Spacer(); Button("Sync Now") { model.syncNow(userInitiated: true) }
                            }
                            if let issue = model.syncIssue {
                                Text("Sync will retry. \(issue)").font(.system(size: 11)).foregroundStyle(Palette.violet)
                            }
                            if model.hasPendingSync {
                                Text("Changes are waiting in memory. They will be lost if you lock or quit before the vault is available.")
                                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                        }
                    } else if storage != .memory {
                        Toggle("Save pinned items only", isOn: $pinnedOnly)
                        Text("Local vaults use this Mac's Keychain. A copied vault requires the original key to reopen.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    HStack {
                        Text("Current: \(model.storageLabel)").foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(model.isAuthenticating ? "Authenticating…" : "Apply Storage") {
                            let phrase = syncPassphrase; syncPassphrase = ""
                            Task { await model.applyStorage(storage, pinnedOnly: pinnedOnly, syncPassphrase: phrase) }
                        }.disabled(model.isLocked || model.isDemo || model.isAuthenticating || (storage == model.preferences.storageMode && pinnedOnly == model.preferences.persistPinnedOnly))
                    }
                }
                section("Retention", symbol: "clock.arrow.circlepath") {
                    Picker("Keep for", selection: Binding(get: { model.preferences.retentionDays }, set: { model.updatePreferences(retention: $0) })) {
                        Text("1 day").tag(1); Text("7 days").tag(7); Text("30 days").tag(30)
                    }
                    Picker("Maximum clips", selection: Binding(get: { model.preferences.maximumEntries }, set: { model.updatePreferences(maximum: $0) })) {
                        Text("100").tag(100); Text("300").tag(300); Text("1,000").tag(1_000)
                    }
                    Picker("Clear copied output after", selection: Binding(get: { model.preferences.clearClipboardAfterSeconds }, set: { model.updatePreferences(clearAfter: $0) })) {
                        Text("15 seconds").tag(15); Text("45 seconds").tag(45); Text("2 minutes").tag(120); Text("Never").tag(0)
                    }
                    Toggle("Keep pins past expiry", isOn: Binding(get: { model.preferences.keepPinsPastExpiry }, set: { model.setKeepPinsPastExpiry($0) }))
                        .disabled(model.isLocked)
                    Text("Pins count toward the history limits. With iCloud, use the same retention settings on all Macs.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                section("Privacy & capture", symbol: "shield.lefthalf.filled") {
                    Toggle("Capture images", isOn: Binding(get: { model.preferences.captureImages }, set: { model.setCaptureImages($0) }))
                    Toggle("Search text in images", isOn: Binding(get: { model.preferences.imageTextSearch }, set: { model.setImageTextSearch($0) }))
                    Text("Reads text on this Mac from up to 60 recent images while the selector is open. The search index lives only in the selector.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Toggle("Capture files", isOn: Binding(get: { model.preferences.captureFiles }, set: { model.setCaptureFiles($0) }))
                    Toggle("Paste on selection", isOn: Binding(get: { model.preferences.autoPaste }, set: { model.setAutoPaste($0) }))
                    Toggle("Clear history when Mac locks or sleeps", isOn: Binding(
                        get: { model.preferences.clearHistoryOnSessionLock },
                        set: { model.setClearHistoryOnSessionLock($0) }))
                        .disabled(model.isLocked)
                    Text("When off, the session stays in memory and capture resumes when you return.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    PermissionStatusView(isDemo: model.isDemo)
                    Text("Image pixels are preferred over accompanying links. Files are limited to 8 MB; folders, multiple-file copies, credential vaults and key files are skipped. Image and binary file content is not scanned for every possible secret. Source attribution is best effort.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("\(model.skippedCount) captures skipped this session").foregroundStyle(Palette.secondary)
                        Spacer(); Button("Exclude an App…") { model.excludeApplication() }.disabled(model.isLocked || model.isDemo)
                    }
                    ForEach(model.preferences.excludedBundleIDs.sorted(), id: \.self) { identifier in
                        HStack {
                            Text(identifier).lineLimit(1).truncationMode(.middle)
                            Spacer(); Button("Remove") { model.removeExclusion(identifier) }
                        }
                    }
                }
                section("Folders", symbol: "folder") {
                    HStack {
                        TextField("New folder", text: $newFolder).textFieldStyle(.roundedBorder)
                        Button("Create") {
                            do {
                                try model.saveFolder(name: newFolder)
                                newFolder = ""
                            } catch { model.errorMessage = error.localizedDescription }
                        }.disabled(model.isLocked || newFolder.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(model.snapshot.collections) { collection in
                        HStack {
                            Text(collection.name); Spacer()
                            Button("Remove") { model.deleteCollection(collection.id) }.disabled(model.isLocked)
                        }
                    }
                    Text("Use the selector’s Folders menu to rename a folder. Removing a folder moves its clips to Unfiled.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                section("On your Mac", symbol: "desktopcomputer") {
                    Picker("Selector shortcut", selection: Binding(get: { model.preferences.selectorShortcut },
                        set: { shortcut in onShortcutChange(shortcut) })) {
                        ForEach(SelectorShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Selector layout", selection: Binding(get: { model.preferences.selectorLayout }, set: { model.setSelectorLayout($0) })) {
                        Text("Pinned left · recent right").tag(SelectorLayout.pinnedAndRecent)
                        Text("Single orbit").tag(SelectorLayout.orbit)
                    }
                    Toggle("Open at login", isOn: $loginEnabled).disabled(model.isDemo)
                        .onChange(of: loginEnabled) { _, enabled in
                            do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { model.errorMessage = "Move CopyTaste to Applications and try the login setting again. \(error.localizedDescription)"; loginEnabled = SMAppService.mainApp.status == .enabled }
                        }
                    Text("Return pastes · Option-Return copies · ⌘1–9 quick paste · ⌘E edits · ⌘B adds to batch")
                        .foregroundStyle(Palette.secondary)
                    Text("CopyTaste \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0") · by tagmat · MIT License")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
            }.padding(30)
        }.background(Palette.background).foregroundStyle(Palette.text).tint(Palette.mint).preferredColorScheme(.dark)
            .frame(minWidth: 600, minHeight: 600)
            .onAppear { storage = model.preferences.storageMode; pinnedOnly = model.preferences.persistPinnedOnly }
            .onChange(of: storage) { _, mode in if mode == .iCloud { pinnedOnly = false } }
            .onChange(of: model.preferences.storageMode) { _, mode in storage = mode }
            .alert("CopyTaste", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private func section<Content: View>(_ name: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(name, systemImage: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.mint)
            content().font(.system(size: 12))
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}
