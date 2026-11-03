import SwiftUI
import ServiceManagement
import CopyTasteCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var storage: StorageMode = .memory
    @State private var pinnedOnly = false
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var syncPassphrase = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your history. Your rules.").font(.system(size: 28, weight: .medium, design: .serif))
                        Text("Choose what stays, where it lives, and when it goes.")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button("Done") { model.showSettings = false }.keyboardShortcut(.escape, modifiers: [])
                }
                section("Storage", icon: "externaldrive") {
                    Picker("Keep history in", selection: $storage) {
                        Text("Memory only · default").tag(StorageMode.memory)
                        Text("Encrypted vault on this Mac").tag(StorageMode.encryptedLocal)
                        Text("Encrypted vault in a chosen folder").tag(StorageMode.encryptedFolder)
                        Text("iCloud Drive · encrypted sync").tag(StorageMode.iCloud)
                    }.pickerStyle(.menu)
                    Text(storage == .memory ? "Clipboard content stays in RAM. Quitting, locking or sleeping clears the session. macOS may still page memory to disk; use FileVault to protect your Mac." : (storage == .iCloud ? "A shared AES-256-GCM vault in iCloud Drive. Your sync passphrase unlocks the same encrypted history on each Mac." : "AES-256-GCM encryption with a device-local Keychain key. Opening saved history requires your Mac password or Touch ID. The key is not included in the vault file."))
                        .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.secondary)
                    Toggle("Save pinned items only", isOn: $pinnedOnly).disabled(storage == .memory || storage == .iCloud)
                    if storage == .iCloud {
                        SecureField("Sync passphrase (16+ characters)", text: $syncPassphrase)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("iCloud sync passphrase")
                        Text("Use the same passphrase on each Mac. It encrypts all synced clips, pins and collections before iCloud Drive sees them. It is not saved and cannot be recovered. Enter it again after locking or restarting.")
                            .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.secondary)
                        Text("iCloud Drive must be enabled on every Mac. Leaving sync does not remove the shared encrypted cloud file.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        if let date = model.lastSyncAt {
                            HStack {
                                Text("Last local merge: \(date.formatted(date: .omitted, time: .shortened))").font(.system(size: 11))
                                Spacer()
                                Button("Sync Now") { model.syncNow(userInitiated: true) }
                            }
                        }
                    } else if storage != .memory {
                        Text("Unpinned items remain in RAM when this option is enabled. Pinned items still expire.")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    HStack {
                        Text("Current: \(model.storageLabel)").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(model.isAuthenticating ? "Authenticating…" : "Apply Storage") {
                            let phrase = syncPassphrase
                            syncPassphrase = ""
                            Task { await model.applyStorage(storage, pinnedOnly: pinnedOnly, syncPassphrase: phrase) }
                        }.disabled(model.isDemo || model.isAuthenticating || (storage == model.preferences.storageMode && pinnedOnly == model.preferences.persistPinnedOnly))
                    }
                    Text(storage == .iCloud ? "Setup merges your current history into the shared encrypted file, then removes the previous local vault. Disconnecting later leaves the shared iCloud file available to other Macs." : "Changing local storage moves the current history and removes the previous local vault. A chosen folder may upload encrypted files through its provider. Local vaults require this Mac's keychain; shared iCloud files remain after disconnecting.")
                        .font(.system(size: 10)).lineSpacing(3).foregroundStyle(Palette.secondary)
                }
                section("Retention", icon: "clock.arrow.circlepath") {
                    Picker("Delete entries after", selection: Binding(get: { model.preferences.retentionDays }, set: { model.updatePreferences(retention: $0) })) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    Picker("Maximum entries", selection: Binding(get: { model.preferences.maximumEntries }, set: { model.updatePreferences(maximum: $0) })) {
                        Text("100").tag(100)
                        Text("300").tag(300)
                        Text("1,000").tag(1_000)
                    }
                    Picker("Clear clipboard after copying", selection: Binding(get: { model.preferences.clearClipboardAfterSeconds }, set: { model.updatePreferences(clearAfter: $0) })) {
                        Text("15 seconds").tag(15)
                        Text("45 seconds").tag(45)
                        Text("2 minutes").tag(120)
                        Text("Never").tag(0)
                    }
                    Text("Auto-clear applies only to items copied from CopyTaste, and never clears a newer clipboard item. History is limited to 24 MB of content; oldest entries expire first, including pins.")
                        .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.secondary)
                }
                section("Protection", icon: "shield.lefthalf.filled") {
                    Label("Private clipboard markers are always respected", systemImage: "checkmark")
                    Label("Credential apps and secure input are excluded", systemImage: "checkmark")
                    Label("Common tokens, private keys and payment numbers are filtered", systemImage: "checkmark")
                    Toggle("Capture images", isOn: Binding(get: { model.preferences.captureImages }, set: { model.setCaptureImages($0) }))
                    Text("Images are off by default: their contents are not scanned for secrets. Source attribution on macOS is best effort. A password copied as ordinary text in a browser may not be detected. Exclude any app you use for sensitive work.")
                        .font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.secondary)
                    HStack {
                        Text("\(model.skippedCount) captures skipped this session").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button("Exclude an App…") { model.excludeApplication() }.disabled(model.isDemo)
                    }
                    ForEach(model.preferences.excludedBundleIDs.sorted(), id: \.self) { identifier in
                        HStack {
                            Text(identifier).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Remove") { model.removeExclusion(identifier) }.font(.system(size: 11))
                        }
                    }
                }
                section("On your Mac", icon: "desktopcomputer") {
                    Toggle("Open CopyTaste at login", isOn: $loginEnabled)
                        .disabled(model.isDemo)
                        .onChange(of: loginEnabled) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                model.errorMessage = "Login setting could not be changed. Move CopyTaste to Applications and try again. \(error.localizedDescription)"
                                loginEnabled = SMAppService.mainApp.status == .enabled
                            }
                        }
                    HStack { Text("Show picker"); Spacer(); Text("⇧ ⌘ V").foregroundStyle(Palette.secondary) }
                    HStack { Text("Search"); Spacer(); Text("⌘ F").foregroundStyle(Palette.secondary) }
                    HStack { Text("Copy selected clip"); Spacer(); Text("⌘ Return").foregroundStyle(Palette.secondary) }
                    Text("CopyTaste 0.1.0 · by tagmat · MIT License")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.top, 8)
                }
            }.padding(32).frame(maxWidth: 750).frame(maxWidth: .infinity)
        }.background(Palette.paper)
            .onAppear { storage = model.preferences.storageMode; pinnedOnly = model.preferences.persistPinnedOnly }
            .onChange(of: model.preferences.storageMode) { _, value in storage = value }
            .onChange(of: storage) { _, value in if value == .iCloud { pinnedOnly = false } }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold))
            content().font(.system(size: 12))
        }.padding(.bottom, 24).overlay(alignment: .bottom) { Rectangle().fill(Palette.divider).frame(height: 1) }
    }
}
