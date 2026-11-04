import AppKit
import Combine
import CryptoKit
import LocalAuthentication
import ServiceManagement
import CopyTasteCore

enum HistoryScope: Hashable {
    case all, pinned, kind(ClipKind), collection(UUID)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = VaultSnapshot()
    @Published private(set) var preferences: Preferences
    @Published private(set) var isLocked = false
    @Published private(set) var isCapturing = false
    @Published private(set) var skippedCount = 0
    @Published var scope: HistoryScope = .all
    @Published var query = ""
    @Published var selectedID: UUID?
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var isAuthenticating = false
    @Published var showSettings = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var syncIssue: String?
    @Published private(set) var hasPendingSync = false
    let isDemo: Bool
    private var key: SymmetricKey?
    private var monitor: ClipboardMonitor?
    private var observers: [NSObjectProtocol] = []
    private var maintenanceTimer: Timer?
    private var clearTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var ownedClipboardCount: Int?
    private var lockEpoch = 0
    private var cloudVault: CloudVault?
    private var syncState = SyncState()
    private var syncTimer: Timer?
    private var syncFailures = 0
    private var nextSyncAttempt = ContinuousClock.now
    private let transfers = TransferFileStore()
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private let authenticateOwner: () async throws -> Void
    private let cloudLocation: () throws -> URL

    init(demo: Bool = false, defaults: UserDefaults = .standard, pasteboard: NSPasteboard? = nil,
         authenticateOwner: @escaping () async throws -> Void = DeviceAuthentication.authenticate,
         cloudLocation: @escaping () throws -> URL = CloudVault.iCloudURL) {
        isDemo = demo
        self.defaults = defaults
        self.authenticateOwner = authenticateOwner
        self.cloudLocation = cloudLocation
        self.pasteboard = pasteboard ?? (demo ? NSPasteboard(name: .init("net.tagmat.copytaste.demo." + UUID().uuidString)) : .general)
        if !demo, let data = defaults.data(forKey: "preferences.v1"),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) {
            preferences = saved
        } else { preferences = Preferences() }
        isLocked = preferences.storageMode != .memory
        if demo {
            snapshot = DemoContent.snapshot()
            selectedID = snapshot.entries.first?.id
        } else {
            let monitor = ClipboardMonitor(pasteboard: self.pasteboard)
            self.monitor = monitor
            monitor.onCapture = { [weak self] entry in self?.capture(entry) }
            monitor.onRejection = { [weak self] reason in
                if reason != .selfWrite { self?.skippedCount += 1 }
            }
            configureMonitor()
            observeLocking()
            maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.prune() }
            }
            syncTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.syncNow() }
            }
        }
    }

    var visibleEntries: [ClipEntry] {
        let scoped = snapshot.entries.filter { entry in
            switch scope {
            case .all: true
            case .pinned: entry.isPinned
            case .kind(let kind): entry.kind == kind
            case .collection(let id): entry.collectionID == id
            }
        }
        return History.search(scoped, query: query)
    }

    var selectedEntry: ClipEntry? { snapshot.entries.first { $0.id == selectedID } }
    var scopeTitle: String {
        switch scope {
        case .all: "Clipboard"
        case .pinned: "Pinned"
        case .kind(.text): "Text"
        case .kind(.link): "Links"
        case .kind(.image): "Images"
        case .kind(.file): "Files"
        case .collection(let id): snapshot.collections.first { $0.id == id }?.name ?? "Collection"
        }
    }
    var storageLabel: String {
        switch preferences.storageMode {
        case .memory: "Memory only"
        case .encryptedLocal: "Encrypted on this Mac"
        case .encryptedFolder: "Encrypted in your folder"
        case .iCloud: "iCloud · encrypted sync"
        }
    }

    private var vaultURL: URL? { vaultURL(for: preferences) }
    private func vaultURL(for settings: Preferences) -> URL? {
        switch settings.storageMode {
        case .memory: return nil
        case .iCloud: return nil
        case .encryptedLocal:
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("net.tagmat.copytaste", isDirectory: true).appendingPathComponent("history.vault")
        case .encryptedFolder:
            return settings.customFolderPath.map { URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent("CopyTaste", isDirectory: true).appendingPathComponent("history.vault") }
        }
    }

    private func archived(_ state: VaultSnapshot, settings: Preferences) -> VaultSnapshot {
        var result = state
        if settings.persistPinnedOnly { result.entries.removeAll { !$0.isPinned } }
        return result
    }

    @discardableResult private func commit(_ state: VaultSnapshot, clearAll: Bool = false) -> Bool {
        guard !isLocked else { return false }
        if preferences.storageMode == .iCloud {
            guard clearAll || state != snapshot else { return true }
            var pending = syncState
            if clearAll { pending.clearedAt = Date() }
            pending.recordChanges(from: snapshot, to: state)
            guard pending.deletionLogWithinLimits else {
                storageFailed(CloudVaultError.tooManyDeletes)
                return false
            }
            syncState = pending
            snapshot = state
            hasPendingSync = true
            syncNow()
            return true
        }
        do {
            if let url = vaultURL {
                guard let key else { throw KeyStoreError.missing }
                try EncryptedVault(url: url).save(archived(state, settings: preferences), key: key)
            }
            snapshot = state
            return true
        } catch {
            storageFailed(error)
            return false
        }
    }

    private func storageFailed(_ error: Error) {
        isCapturing = false
        preferences.captureEnabled = false
        savePreferences()
        monitor?.stop()
        errorMessage = "Capture is paused. \(error.localizedDescription) No unencrypted fallback was written."
    }

    private func capture(_ entry: ClipEntry) {
        guard !isLocked, isCapturing else { return }
        commit(History.inserting(entry, into: snapshot, preferences: preferences))
        if selectedID == nil { selectedID = snapshot.entries.first?.id }
    }

    func prune() {
        guard !isLocked else { return }
        let updated = History.pruned(snapshot, preferences: preferences)
        if updated != snapshot { commit(updated) }
    }

    func toggleCapture() {
        guard !isDemo, !isLocked else { return }
        preferences.captureEnabled = !isCapturing
        savePreferences()
        configureMonitor()
    }

    private func configureMonitor() {
        monitor?.policy = CapturePolicy(excludedBundleIDs: preferences.excludedBundleIDs)
        monitor?.captureImages = preferences.captureImages
        monitor?.captureFiles = preferences.captureFiles
        isCapturing = preferences.captureEnabled && !isLocked && !isDemo
        if isCapturing { monitor?.start() } else { monitor?.stop() }
    }

    @discardableResult func copy(_ entry: ClipEntry) -> Bool {
        guard !isLocked else { return false }
        let item = NSPasteboardItem()
        item.setString("CopyTaste", forType: .init("net.tagmat.copytaste.origin"))
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        if entry.kind == .file {
            do { item.setString(try transfers.materialize(entry).absoluteString, forType: .fileURL) }
            catch { errorMessage = "The file could not be prepared for pasting. \(error.localizedDescription)"; return false }
        } else if entry.kind == .image, let image = entry.imageData { item.setData(image, forType: .png) }
        else if let text = entry.text { item.setString(text, forType: .string) }
        else { return false }
        clearTask?.cancel()
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { errorMessage = "The clipboard could not be updated. Try again."; return false }
        ownedClipboardCount = pasteboard.changeCount
        let expectedCount = pasteboard.changeCount
        let seconds = preferences.clearClipboardAfterSeconds
        if seconds > 0 {
            clearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                if self.pasteboard.changeCount == expectedCount { self.pasteboard.clearContents() }
            }
        }
        notify(isDemo ? "Copied to the isolated demo clipboard" : "Copied · paste with ⌘V")
        return true
    }

    var ownsCurrentClipboard: Bool {
        ownedClipboardCount == pasteboard.changeCount
    }

    func saveClip(id: UUID?, title: String, text: String?) -> String? {
        guard !isLocked else { return "Unlock history to edit clips." }
        let policy = CapturePolicy()
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.count > 120 || label.utf8.count > 512 { return "Use a shorter title." }
        if !label.isEmpty && policy.rejection(forText: label) != nil { return "The title may contain sensitive data." }
        var state = snapshot
        let now = Date()
        let index = id.flatMap { id in state.entries.firstIndex { $0.id == id } }
        if id != nil && index == nil { return "This clip is no longer in history." }
        var entry = index.map { state.entries[$0] } ?? ClipEntry(kind: .text, sourceName: "Snippet", sourceBundleID: CapturePolicy.ownBundleID, createdAt: now)
        if entry.kind == .text || entry.kind == .link {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter some text." }
            if text.utf8.count > CapturePolicy.maxTextBytes { return "Text exceeds the 512 KB limit." }
            if policy.rejection(forText: text) != nil { return "The text may contain sensitive data." }
            if text != entry.text {
                entry.text = text
                entry.kind = CapturePolicy.kind(for: text)
                entry.createdAt = now
                let fingerprint = entry.fingerprint
                if state.entries.contains(where: { $0.id != entry.id && $0.kind == entry.kind && $0.byteCount == entry.byteCount && $0.fingerprint == fingerprint }) {
                    return "A clip with this content already exists."
                }
                // A body replacement tombstones the old fingerprint in shared history.
                if index != nil { entry.id = UUID() }
            }
        }
        entry.title = label.isEmpty ? nil : label
        entry.modifiedAt = now
        if let index { state.entries[index] = entry }
        else { state.entries.insert(entry, at: 0) }
        state = History.pruned(state, preferences: preferences)
        guard state.entries.contains(where: { $0.id == entry.id }) else { return "History is at its limit. Remove a clip or raise the limit." }
        guard commit(state) else { return "The clip could not be saved." }
        selectedID = entry.id
        return nil
    }

    func togglePin(_ entry: ClipEntry) {
        var state = snapshot
        guard let index = state.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        state.entries[index].isPinned.toggle()
        state.entries[index].modifiedAt = Date()
        commit(state)
    }

    func delete(_ entry: ClipEntry) {
        var state = snapshot
        state.entries.removeAll { $0.id == entry.id }
        commit(state)
        if selectedID == entry.id { selectedID = visibleEntries.first?.id }
    }

    func clearHistory() {
        commit(VaultSnapshot(collections: snapshot.collections), clearAll: true)
        selectedID = nil
        clearOwnedClipboard()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
    }

    func createCollection(_ name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, snapshot.collections.count < 30,
              !snapshot.collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return }
        var state = snapshot
        let collection = ClipCollection(name: name)
        state.collections.append(collection)
        commit(state)
        scope = .collection(collection.id)
    }

    func deleteCollection(_ id: UUID) {
        var state = snapshot
        state.collections.removeAll { $0.id == id }
        for index in state.entries.indices where state.entries[index].collectionID == id { state.entries[index].collectionID = nil }
        commit(state)
        scope = .all
    }

    func move(_ entry: ClipEntry, to collection: UUID?) {
        var state = snapshot
        guard let index = state.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        state.entries[index].collectionID = collection
        state.entries[index].modifiedAt = Date()
        commit(state)
    }

    func updatePreferences(retention: Int? = nil, maximum: Int? = nil, clearAfter: Int? = nil) {
        if let retention { preferences.retentionDays = retention }
        if let maximum { preferences.maximumEntries = maximum }
        if let clearAfter { preferences.clearClipboardAfterSeconds = clearAfter }
        savePreferences()
        prune()
    }

    func excludeApplication() {
        let picker = NSOpenPanel()
        picker.title = "Exclude an application"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url,
              let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        preferences.excludedBundleIDs.insert(identifier)
        // Remove previously captured content from a newly excluded app immediately.
        var state = snapshot
        state.entries.removeAll { $0.sourceBundleID.caseInsensitiveCompare(identifier) == .orderedSame }
        commit(state)
        savePreferences()
        configureMonitor()
    }

    func removeExclusion(_ identifier: String) {
        preferences.excludedBundleIDs.remove(identifier)
        savePreferences()
        configureMonitor()
    }

    func setCaptureImages(_ enabled: Bool) {
        preferences.captureImages = enabled
        savePreferences()
        configureMonitor()
    }

    func setAutoPaste(_ enabled: Bool) {
        preferences.autoPaste = enabled
        savePreferences()
    }

    func setCaptureFiles(_ enabled: Bool) {
        preferences.captureFiles = enabled
        savePreferences()
        configureMonitor()
    }

    func setSelectorLayout(_ layout: SelectorLayout) {
        preferences.selectorLayout = layout
        savePreferences()
    }

    func setSelectorShortcut(_ shortcut: SelectorShortcut) {
        preferences.selectorShortcut = shortcut
        savePreferences()
    }

    func setImageTextSearch(_ enabled: Bool) {
        preferences.imageTextSearch = enabled
        savePreferences()
    }

    func setKeepPinsPastExpiry(_ enabled: Bool) {
        preferences.keepPinsPastExpiry = enabled
        savePreferences()
        prune()
    }

    func applyStorage(_ mode: StorageMode, pinnedOnly: Bool, syncPassphrase: String = "") async {
        guard !isDemo, !isLocked, !isAuthenticating else { return }
        var next = preferences
        next.storageMode = mode
        next.persistPinnedOnly = pinnedOnly
        if mode == .iCloud {
            await enableCloudSync(passphrase: syncPassphrase)
            return
        }
        if mode == .encryptedFolder && (preferences.storageMode != mode || preferences.customFolderPath == nil) {
            let picker = NSOpenPanel()
            picker.title = "Choose a folder for the encrypted vault"
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            picker.canCreateDirectories = true
            guard picker.runModal() == .OK, let folder = picker.url else { return }
            next.customFolderPath = folder.path
        }
        let oldURL = vaultURL
        let newURL = vaultURL(for: next)
        do {
            var nextKey = key
            if let newURL {
                if newURL != oldURL && FileManager.default.fileExists(atPath: newURL.path) {
                    errorMessage = "This folder already contains a vault. Choose an empty folder to avoid replacing saved history."
                    return
                }
                if key == nil {
                    try await authenticate()
                    guard !isLocked else { return }
                    nextKey = try KeyStore().load(allowCreation: true)
                }
                guard let nextKey else { throw KeyStoreError.missing }
                try EncryptedVault(url: newURL).save(archived(snapshot, settings: next), key: nextKey)
            }
            if let oldURL, oldURL != newURL, FileManager.default.fileExists(atPath: oldURL.path) {
                do { try FileManager.default.removeItem(at: oldURL) }
                catch {
                    if let newURL { try? FileManager.default.removeItem(at: newURL) }
                    throw error
                }
            }
            preferences = next
            key = mode == .memory ? nil : nextKey
            cloudVault = nil
            syncState = SyncState()
            resetSyncStatus()
            savePreferences()
            notify("Storage updated · \(storageLabel)")
        } catch { errorMessage = "Storage was not changed. \(error.localizedDescription)" }
    }

    private func authenticate() async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        try await authenticateOwner()
    }

    func unlock(syncPassphrase: String = "") async {
        guard isLocked, !isAuthenticating else { return }
        let epoch = lockEpoch
        do {
            if preferences.storageMode == .iCloud {
                try await authenticate()
                guard lockEpoch == epoch else { return }
                isAuthenticating = true
                defer { isAuthenticating = false }
                let url = try cloudLocation()
                let connected = try await Task.detached(priority: .userInitiated) {
                    try CloudVault.connect(url: url, passphrase: syncPassphrase, createIfMissing: false)
                }.value
                guard lockEpoch == epoch else { return }
                let exchanged = try connected.exchange(SyncState(), preferences: preferences)
                cloudVault = connected
                syncState = exchanged
                snapshot = exchanged.snapshot
                resetSyncStatus(lastMerge: Date())
            } else if let url = vaultURL {
                try await authenticate()
                guard lockEpoch == epoch else { return }
                let loadedKey = try KeyStore().load(allowCreation: !FileManager.default.fileExists(atPath: url.path))
                let saved = try EncryptedVault(url: url).load(key: loadedKey)
                let pruned = History.pruned(saved, preferences: preferences)
                try EncryptedVault(url: url).save(archived(pruned, settings: preferences), key: loadedKey)
                key = loadedKey
                snapshot = pruned
            }
            isLocked = false
            selectedID = snapshot.entries.first?.id
            configureMonitor()
        } catch { errorMessage = "History remains locked. \(error.localizedDescription)" }
    }

    func lock() {
        guard !isDemo else { return }
        lockEpoch += 1
        monitor?.stop()
        isCapturing = false
        clearOwnedClipboard()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
        snapshot = VaultSnapshot()
        key = nil
        cloudVault = nil
        syncState = SyncState()
        resetSyncStatus()
        selectedID = nil
        query = ""
        scope = .all
        showSettings = false
        isLocked = true
    }

    private func clearOwnedClipboard() {
        clearTask?.cancel()
        if let ownedClipboardCount, pasteboard.changeCount == ownedClipboardCount { pasteboard.clearContents() }
        ownedClipboardCount = nil
    }

    func shutdown() {
        monitor?.stop(); syncTimer?.invalidate(); maintenanceTimer?.invalidate()
        clearOwnedClipboard(); snapshot = VaultSnapshot(); key = nil; cloudVault = nil; syncState = SyncState()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
    }

    private func enableCloudSync(passphrase: String) async {
        let epoch = lockEpoch
        do {
            let url = try cloudLocation()
            try await authenticate()
            guard !isLocked, epoch == lockEpoch else { return }
            isAuthenticating = true
            defer { isAuthenticating = false }
            let connected = try await Task.detached(priority: .userInitiated) {
                try CloudVault.connect(url: url, passphrase: passphrase)
            }.value
            guard !isLocked, epoch == lockEpoch else { return }
            var next = preferences
            next.storageMode = .iCloud
            next.persistPinnedOnly = false
            let exchanged = try connected.exchange(SyncState(snapshot: snapshot), preferences: next)
            // A shared iCloud vault is never removed when another mode is selected.
            if let old = vaultURL, FileManager.default.fileExists(atPath: old.path) { try FileManager.default.removeItem(at: old) }
            preferences = next
            cloudVault = connected
            syncState = exchanged
            snapshot = exchanged.snapshot
            key = nil
            resetSyncStatus(lastMerge: Date())
            savePreferences()
            notify("iCloud sync enabled · encrypted with your sync passphrase")
        } catch { errorMessage = "iCloud sync was not enabled. \(error.localizedDescription)" }
    }

    func syncNow(userInitiated: Bool = false) {
        guard !isLocked, preferences.storageMode == .iCloud, let cloudVault,
              userInitiated || ContinuousClock.now >= nextSyncAttempt else { return }
        do {
            let exchanged = try cloudVault.exchange(syncState, preferences: preferences)
            syncState = exchanged
            if snapshot != exchanged.snapshot { snapshot = exchanged.snapshot }
            resetSyncStatus(lastMerge: Date())
        } catch {
            syncFailures = min(syncFailures + 1, 5)
            nextSyncAttempt = ContinuousClock.now + .seconds(min(90, 6 << (syncFailures - 1)))
            syncIssue = error.localizedDescription
            if userInitiated { errorMessage = "Sync could not merge. \(error.localizedDescription)" }
        }
    }

    private func resetSyncStatus(lastMerge: Date? = nil) {
        lastSyncAt = lastMerge
        syncIssue = nil
        hasPendingSync = false
        syncFailures = 0
        nextSyncAttempt = ContinuousClock.now
    }

    private func observeLocking() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.lock() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.lock() }
            })
    }

    private func savePreferences() {
        guard !isDemo, let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: "preferences.v1")
    }

    func notify(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

@MainActor
enum DeviceAuthentication {
    static func authenticate() async throws {
        let context = LAContext()
        var reason: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &reason) else {
            throw reason ?? NSError(domain: "CopyTaste", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Set a Mac login password to use encrypted storage."])
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open CopyTaste encrypted history")
    }
}
