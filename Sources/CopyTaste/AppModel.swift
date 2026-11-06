import AppKit
import Combine
import CryptoKit
import LocalAuthentication
import Carbon
import CopyTasteCore

private enum FolderError: LocalizedError {
    case locked, invalidName, duplicateName, limit, missingFolder, missingClip, saveFailed

    var errorDescription: String? {
        switch self {
        case .locked: "Unlock history to manage folders."
        case .invalidName: "Enter a folder name of up to 40 characters on one line."
        case .duplicateName: "A folder already has that name."
        case .limit: "History can hold up to 30 folders."
        case .missingFolder: "This folder was removed."
        case .missingClip: "This clip is no longer in history."
        case .saveFailed: "The folder could not be saved."
        }
    }
}

private enum SessionSuspension: Hashable, Sendable {
    case systemSleep, displaySleep, inactiveSession, screenLock
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = VaultSnapshot()
    @Published private(set) var preferences: Preferences
    @Published private(set) var isLocked = false
    @Published private(set) var isCapturing = false
    @Published private(set) var skippedCount = 0
    @Published var selectedID: UUID?
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published var isAuthenticating = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var syncIssue: String?
    @Published private(set) var hasPendingSync = false
    @Published private(set) var hasPendingLocalSave = false
    @Published private(set) var lastCaptureIssue: String?
    private let worker = VaultWorker()
    private var storageTask: Task<Void, Never>?
    private var runningSync: Task<Void, Never>?
    private var revision = 0
    private var storageTransition = false
    let isDemo: Bool
    private var key: SymmetricKey?
    private var monitor: ClipboardMonitor?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    @Published private var sessionSuspensions: Set<SessionSuspension> = []
    private var resumeAfterSession = false
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
    private let localLocation: () -> URL
    private let loadKey: (Bool) throws -> SymmetricKey
    private let sessionIsActive: @MainActor () -> Bool

    init(demo: Bool = false, defaults: UserDefaults = .standard, pasteboard: NSPasteboard? = nil,
         authenticateOwner: @escaping () async throws -> Void = DeviceAuthentication.authenticate,
         cloudLocation: @escaping () throws -> URL = CloudVault.iCloudURL,
         localLocation: @escaping () -> URL = { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("net.tagmat.copytaste", isDirectory: true).appendingPathComponent("history.vault") },
         loadKey: @escaping (Bool) throws -> SymmetricKey = { try KeyStore().load(allowCreation: $0, context: DeviceAuthentication.context) },
         sessionIsActive: @escaping @MainActor () -> Bool = SessionState.isActive,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         screenNotifications: NotificationCenter = DistributedNotificationCenter.default(),
         makeMonitor: (NSPasteboard) -> ClipboardMonitor = { ClipboardMonitor(pasteboard: $0) }) {
        isDemo = demo
        self.defaults = defaults
        self.authenticateOwner = authenticateOwner
        self.cloudLocation = cloudLocation
        self.localLocation = localLocation
        self.loadKey = loadKey
        self.sessionIsActive = sessionIsActive
        self.pasteboard = pasteboard ?? (demo ? NSPasteboard(name: .init("net.tagmat.copytaste.demo." + UUID().uuidString)) : .general)
        preferences = Preferences()
        if !demo, let data = defaults.data(forKey: "preferences.v1") {
            do {
                preferences = try JSONDecoder().decode(Preferences.self, from: data)
                if !preferences.recoveryWarnings.isEmpty {
                    defaults.set(data, forKey: "preferences.recovery.v1")
                    errorMessage = "Some settings could not be read. Capture is paused. Review storage and app exclusions before enabling capture. The original settings were preserved for recovery."
                }
            } catch {
                defaults.set(data, forKey: "preferences.recovery.v1")
                errorMessage = "Settings could not be read. Capture is off and the original settings were preserved for recovery. Saved vault files have not been changed."
            }
        }
        isLocked = preferences.storageMode != .memory
        if demo {
            snapshot = DemoContent.snapshot()
            selectedID = snapshot.entries.first?.id
        } else {
            let monitor = makeMonitor(self.pasteboard)
            self.monitor = monitor
            monitor.onCapture = { [weak self] entry in self?.capture(entry) }
            monitor.onRejection = { [weak self] reason in
                if reason != .selfWrite {
                    self?.skippedCount += 1
                    self?.lastCaptureIssue = reason.captureMessage
                }
            }
            configureMonitor()
            observeSession(workspace: workspaceNotifications, screen: screenNotifications)
            maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.prune() }
            }
            syncTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in await self?.syncNow() }
            }
        }
    }

    var selectedEntry: ClipEntry? { snapshot.entries.first { $0.id == selectedID } }
    var isSessionSuspended: Bool { !sessionSuspensions.isEmpty }
    var sessionEpoch: Int { lockEpoch }
    var hasUnsavedChanges: Bool { hasPendingSync || hasPendingLocalSave }
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
            return localLocation()
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

    @discardableResult private func commit(_ state: VaultSnapshot, clearAll: Bool = false,
                                           explicitDeletion: Bool = false) -> Bool {
        guard !isLocked else { return false }
        guard clearAll || state != snapshot else { return true }
        if preferences.storageMode == .iCloud {
            var pending = syncState
            pending.applyLocalChanges(from: snapshot, to: state, explicitDeletion: explicitDeletion, clearAll: clearAll)
            guard pending.deletionLogWithinLimits else {
                errorMessage = CloudVaultError.tooManyDeletes.localizedDescription
                return false
            }
            syncState = pending
            hasPendingSync = true
        } else if vaultURL != nil {
            guard key != nil else { storageFailed(KeyStoreError.missing); return false }
            hasPendingLocalSave = true
        }
        snapshot = state
        revision += 1
        schedulePersistence()
        return true
    }

    private func schedulePersistence() {
        storageTask?.cancel()
        guard hasUnsavedChanges, !isLocked, !storageTransition else { return }
        storageTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            if self.preferences.storageMode == .iCloud { await self.syncNow() }
            else { _ = await self.flushStorage() }
        }
    }

    @discardableResult func flushStorage() async -> Bool {
        guard !isLocked else { return !hasUnsavedChanges }
        if preferences.storageMode == .iCloud {
            await syncNow(userInitiated: true)
            return !hasPendingSync
        }
        guard hasPendingLocalSave, let url = vaultURL, let key else { return !hasPendingLocalSave }
        let epoch = lockEpoch
        let version = revision
        let state = archived(snapshot, settings: preferences)
        do {
            try await worker.save(state, to: url, key: key)
            guard lockEpoch == epoch, !isLocked else { return false }
            if revision == version { hasPendingLocalSave = false }
            else { schedulePersistence() }
            return !hasPendingLocalSave
        } catch is CancellationError { return false }
        catch {
            guard lockEpoch == epoch else { return false }
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
        let updated = preferences.storageMode == .iCloud ? CloudVault.visibleSnapshot(syncState.snapshot, preferences: preferences) : History.pruned(snapshot, preferences: preferences)
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
        isCapturing = preferences.captureEnabled && !isLocked && !isSessionSuspended && !isDemo
        if isCapturing { monitor?.start() } else { monitor?.stop() }
    }

    @discardableResult func copy(_ entry: ClipEntry) -> Bool {
        guard !isLocked else { return false }
        let item = NSPasteboardItem()
        item.setString("CopyTaste", forType: .init("net.tagmat.copytaste.origin"))
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        var writer: any NSPasteboardWriting = item
        if entry.kind == .file {
            do { writer = FilePasteboardWriter(url: try transfers.materialize(entry)) }
            catch { errorMessage = "The file could not be prepared for pasting. \(error.localizedDescription)"; return false }
        } else if entry.kind == .image, let image = entry.imageData { item.setData(image, forType: .png) }
        else if let text = entry.text { item.setString(text, forType: .string) }
        else { return false }
        clearTask?.cancel()
        pasteboard.clearContents()
        guard pasteboard.writeObjects([writer]) else { errorMessage = "The clipboard could not be updated. Try again."; return false }
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
        if !label.isEmpty && policy.rejection(forText: label, manual: true) != nil { return "The title may contain sensitive data." }
        var state = snapshot
        let now = Date()
        let index = id.flatMap { id in state.entries.firstIndex { $0.id == id } }
        if id != nil && index == nil { return "This clip is no longer in history." }
        var entry = index.map { state.entries[$0] } ?? ClipEntry(kind: .text, sourceName: "Snippet", sourceBundleID: CapturePolicy.ownBundleID, createdAt: now, isPinned: true)
        if entry.kind == .text || entry.kind == .link {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter some text." }
            if text.utf8.count > CapturePolicy.maxTextBytes { return "Text exceeds the 512 KB limit." }
            if policy.rejection(forText: text, manual: true) != nil { return "The text may contain sensitive data." }
            if text != entry.text {
                entry.text = text
                entry.sourceName = "Snippet"
                entry.sourceBundleID = CapturePolicy.ownBundleID
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
        guard commit(state, explicitDeletion: id != nil) else { return "The clip could not be saved." }
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
        commit(state, explicitDeletion: true)
        if selectedID == entry.id { selectedID = snapshot.entries.first?.id }
    }

    func clearHistory() {
        commit(VaultSnapshot(collections: snapshot.collections), clearAll: true)
        selectedID = nil
        clearOwnedClipboard()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
    }

    @discardableResult func saveFolder(name: String, id: UUID? = nil, moving clipID: UUID? = nil) throws -> UUID {
        guard !isLocked else { throw FolderError.locked }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, name.utf8.count <= 160,
              name.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { throw FolderError.invalidName }
        guard !snapshot.collections.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw FolderError.duplicateName }
        var state = snapshot
        let now = Date()
        let folderID: UUID
        if let id {
            guard let index = state.collections.firstIndex(where: { $0.id == id }) else { throw FolderError.missingFolder }
            state.collections[index].name = name
            state.collections[index].modifiedAt = now
            folderID = id
        } else {
            guard state.collections.count < 30 else { throw FolderError.limit }
            let folder = ClipCollection(name: name, modifiedAt: now)
            state.collections.append(folder)
            folderID = folder.id
        }
        if let clipID {
            guard let index = state.entries.firstIndex(where: { $0.id == clipID }) else { throw FolderError.missingClip }
            state.entries[index].collectionID = folderID
            state.entries[index].modifiedAt = now
        }
        guard commit(state) else { throw FolderError.saveFailed }
        return folderID
    }

    @discardableResult func deleteCollection(_ id: UUID) -> Bool {
        guard snapshot.collections.contains(where: { $0.id == id }) else { return false }
        var state = snapshot
        state.collections.removeAll { $0.id == id }
        let now = Date()
        for index in state.entries.indices where state.entries[index].collectionID == id {
            state.entries[index].collectionID = nil
            state.entries[index].modifiedAt = now
        }
        guard commit(state) else { return false }
        return true
    }

    func move(_ entry: ClipEntry, to collection: UUID?) {
        if let collection, !snapshot.collections.contains(where: { $0.id == collection }) { return }
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
        if preferences.storageMode == .iCloud { snapshot = CloudVault.visibleSnapshot(syncState.snapshot, preferences: preferences) }
        else { commit(state) }
        savePreferences()
        configureMonitor()
    }

    func removeExclusion(_ identifier: String) {
        preferences.excludedBundleIDs.remove(identifier)
        if preferences.storageMode == .iCloud { snapshot = CloudVault.visibleSnapshot(syncState.snapshot, preferences: preferences) }
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

    func setClearHistoryOnSessionLock(_ enabled: Bool) {
        preferences.clearHistoryOnSessionLock = enabled
        savePreferences()
    }

    func applyStorage(_ mode: StorageMode, pinnedOnly: Bool, syncPassphrase: String = "") async {
        guard !isDemo, !isLocked, !isAuthenticating, !storageTransition else { return }
        if mode == .iCloud { await enableCloudSync(passphrase: syncPassphrase); return }
        storageTransition = true
        storageTask?.cancel()
        await storageTask?.value
        defer { storageTransition = false; schedulePersistence() }
        let epoch = lockEpoch
        let oldURL = vaultURL
        var folderPath = preferences.customFolderPath
        if mode == .encryptedFolder && (preferences.storageMode != mode || folderPath == nil) {
            let picker = NSOpenPanel()
            picker.title = "Choose a folder for the encrypted vault"
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            picker.canCreateDirectories = true
            guard picker.runModal() == .OK, let folder = picker.url else { return }
            folderPath = folder.path
        }
        do {
            var nextKey = key
            if mode != .memory, nextKey == nil {
                try await authenticate()
                guard !isLocked, lockEpoch == epoch else { return }
                nextKey = try loadKey(true)
            }
            isAuthenticating = true
            defer { isAuthenticating = false }
            // Read the latest preferences after authentication; unrelated choices may have changed.
            var next = preferences
            next.storageMode = mode
            next.persistPinnedOnly = pinnedOnly
            next.customFolderPath = folderPath
            let newURL = vaultURL(for: next)
            if let newURL {
                if newURL != oldURL && FileManager.default.fileExists(atPath: newURL.path) {
                    errorMessage = "This location already contains a vault. Restore its settings or choose an empty folder."
                    return
                }
                guard let nextKey else { throw KeyStoreError.missing }
                try await worker.save(archived(snapshot, settings: next), to: newURL, key: nextKey)
                guard !isLocked, lockEpoch == epoch else { return }
            }
            // Commit the new pointer before removing the old file, so interruption is recoverable.
            preferences.storageMode = mode
            preferences.persistPinnedOnly = pinnedOnly
            preferences.customFolderPath = folderPath
            savePreferences()
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            key = mode == .memory ? nil : nextKey
            cloudVault = nil
            syncState = SyncState()
            resetSyncStatus()
            hasPendingLocalSave = false
            if let oldURL, oldURL != newURL, FileManager.default.fileExists(atPath: oldURL.path) {
                do { try FileManager.default.removeItem(at: oldURL) }
                catch { errorMessage = "Storage was updated, but the previous encrypted copy could not be removed. Remove it after verifying the new vault." }
            }
            if newURL != nil { hasPendingLocalSave = true; schedulePersistence() }
            notify("Storage updated · \(storageLabel)")
        } catch { errorMessage = "Storage could not be updated. \(error.localizedDescription) Existing encrypted copies were preserved." }
    }

    private func authenticate() async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        try await authenticateOwner()
    }

    func unlock(syncPassphrase: String = "") async {
        guard isLocked, !isAuthenticating else { return }
        guard !isSessionSuspended else {
            errorMessage = "The session is still suspended. If your Mac is awake and unlocked, choose Recover Session to verify and resume it."
            return
        }
        let epoch = lockEpoch
        do {
            if preferences.storageMode != .memory { try await authenticate() }
            guard lockEpoch == epoch else { return }
            isAuthenticating = true
            defer { isAuthenticating = false }
            if preferences.storageMode == .iCloud {
                let connected = try await worker.connect(url: cloudLocation(), passphrase: syncPassphrase, create: false)
                let exchanged: SyncState
                var maintenanceIssue: String?
                do { exchanged = try await worker.exchange(SyncState(), vault: connected, preferences: preferences) }
                catch CloudVaultError.tooManyDeletes {
                    exchanged = try await worker.read(connected)
                    maintenanceIssue = CloudVaultError.tooManyDeletes.localizedDescription
                }
                guard lockEpoch == epoch else { return }
                cloudVault = connected
                syncState = exchanged
                snapshot = CloudVault.visibleSnapshot(exchanged.snapshot, preferences: preferences)
                resetSyncStatus(lastMerge: Date())
                syncIssue = maintenanceIssue
            } else if let url = vaultURL {
                guard FileManager.default.fileExists(atPath: url.path) else { throw VaultError.missing }
                let loadedKey = try loadKey(false)
                let saved = try await worker.load(from: url, key: loadedKey)
                guard lockEpoch == epoch else { return }
                let pruned = History.pruned(saved, preferences: preferences)
                key = loadedKey
                snapshot = pruned
                hasPendingLocalSave = pruned != saved
            }
            isLocked = false
            selectedID = snapshot.entries.first?.id
            configureMonitor()
            schedulePersistence()
        } catch { errorMessage = "History remains locked. \(error.localizedDescription)" }
    }

    func recoverSession(syncPassphrase: String = "") async {
        guard isSessionSuspended, !isAuthenticating else { return }
        let epoch = lockEpoch
        do {
            try await authenticate()
            guard lockEpoch == epoch, sessionIsActive() else {
                errorMessage = "Your Mac must be awake, unlocked and in your active session before capture can resume."
                return
            }
            let retained = resumeAfterSession
            sessionSuspensions.removeAll()
            resumeAfterSession = false
            if retained {
                isLocked = false
                prune()
                selectedID = snapshot.entries.first?.id
                configureMonitor()
            } else { await unlock(syncPassphrase: syncPassphrase) }
        } catch { errorMessage = "Session recovery was cancelled or unavailable. \(error.localizedDescription)" }
    }

    func requestLock() {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = "Discard changes waiting to be saved?"
            alert.informativeText = "Locking clears memory. Pending encrypted history changes cannot be recovered. Keep CopyTaste unlocked to retry saving."
            alert.addButton(withTitle: "Keep Unlocked")
            alert.addButton(withTitle: "Discard and Lock")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        lock()
    }

    func lock() {
        guard !isDemo else { return }
        resumeAfterSession = false
        lockEpoch += 1
        storageTask?.cancel()
        runningSync?.cancel()
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
        hasPendingLocalSave = false
        DeviceAuthentication.context = nil
        selectedID = nil
        isLocked = true
    }

    private func clearOwnedClipboard() {
        clearTask?.cancel()
        if let ownedClipboardCount, pasteboard.changeCount == ownedClipboardCount { pasteboard.clearContents() }
        ownedClipboardCount = nil
    }

    func shutdown() {
        resumeAfterSession = false
        lockEpoch += 1
        storageTask?.cancel()
        runningSync?.cancel()
        storageTask?.cancel(); runningSync?.cancel()
        monitor?.stop(); syncTimer?.invalidate(); maintenanceTimer?.invalidate()
        isCapturing = false
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers.removeAll()
        clearOwnedClipboard(); snapshot = VaultSnapshot(); key = nil; cloudVault = nil; syncState = SyncState()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
    }

    private func enableCloudSync(passphrase: String) async {
        storageTransition = true
        storageTask?.cancel()
        await storageTask?.value
        defer { storageTransition = false; schedulePersistence() }
        let epoch = lockEpoch
        do {
            try await authenticate()
            guard !isLocked, epoch == lockEpoch else { return }
            isAuthenticating = true
            defer { isAuthenticating = false }
            let connected = try await worker.connect(url: cloudLocation(), passphrase: passphrase, create: true)
            let sent = snapshot
            let exchanged = try await worker.exchange(SyncState(snapshot: sent), vault: connected, preferences: preferences, allowImport: true)
            guard !isLocked, epoch == lockEpoch else { return }
            let old = vaultURL
            preferences.storageMode = .iCloud
            preferences.persistPinnedOnly = false
            savePreferences()
            guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            cloudVault = connected
            syncState = exchanged
            syncState.applyLocalChanges(from: sent, to: snapshot)
            snapshot = CloudVault.visibleSnapshot(syncState.snapshot, preferences: preferences)
            key = nil
            hasPendingLocalSave = false
            resetSyncStatus(lastMerge: Date())
            hasPendingSync = syncState != exchanged
            if let old, FileManager.default.fileExists(atPath: old.path) {
                do { try FileManager.default.removeItem(at: old) }
                catch { errorMessage = "iCloud sync is enabled, but the previous local encrypted copy could not be removed. Verify sync before removing that copy." }
            }
            schedulePersistence()
            notify("iCloud sync enabled · encrypted with your sync passphrase")
        } catch { errorMessage = "iCloud sync could not be enabled. \(error.localizedDescription) Existing encrypted copies were preserved." }
    }

    func syncNow(userInitiated: Bool = false) async {
        if let runningSync { await runningSync.value; return }
        runningSync = Task { [weak self] in
            guard let self else { return }
            await self.performSync(userInitiated: userInitiated)
        }
        await runningSync?.value
        runningSync = nil
    }

    private func performSync(userInitiated: Bool) async {
        guard !isLocked, preferences.storageMode == .iCloud, let cloudVault,
              userInitiated || ContinuousClock.now >= nextSyncAttempt else { return }
        let epoch = lockEpoch
        let sent = syncState
        do {
            let exchanged = try await worker.exchange(sent, vault: cloudVault, preferences: preferences)
            guard !Task.isCancelled, lockEpoch == epoch, !isLocked, preferences.storageMode == .iCloud else { return }
            let changedWhileSaving = syncState != sent
            syncState = changedWhileSaving ? exchanged.merging(syncState) : exchanged
            syncState.generation = exchanged.generation
            snapshot = CloudVault.visibleSnapshot(syncState.snapshot, preferences: preferences)
            resetSyncStatus(lastMerge: Date())
            hasPendingSync = syncState != exchanged
        } catch is CancellationError { return }
        catch {
            guard lockEpoch == epoch else { return }
            syncFailures = min(syncFailures + 1, 5)
            nextSyncAttempt = ContinuousClock.now + .seconds(min(90, 6 << (syncFailures - 1)))
            syncIssue = error.localizedDescription
            if userInitiated { errorMessage = "Sync could not merge. \(error.localizedDescription)" }
        }
    }

    func compactSyncHistory() async {
        guard !isLocked, !isAuthenticating, let cloudVault else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        await runningSync?.value
        let epoch = lockEpoch
        let sent = syncState
        do {
            var fresh = try await worker.compact(sent, vault: cloudVault)
            guard lockEpoch == epoch, !isLocked else { return }
            if syncState != sent {
                var delta = syncState
                delta.generation = fresh.generation
                fresh = fresh.merging(delta)
            }
            syncState = fresh
            snapshot = CloudVault.visibleSnapshot(fresh.snapshot, preferences: preferences)
            resetSyncStatus(lastMerge: Date())
            hasPendingSync = true
            await syncNow(userInitiated: true)
            notify("Sync history compacted. Reopen sync on your other Macs before editing there.")
        } catch { errorMessage = "Sync history was not compacted. \(error.localizedDescription)" }
    }

    private func resetSyncStatus(lastMerge: Date? = nil) {
        lastSyncAt = lastMerge
        syncIssue = nil
        hasPendingSync = false
        syncFailures = 0
        nextSyncAttempt = ContinuousClock.now
    }

    private func suspendSession(for reason: SessionSuspension) {
        let firstSuspension = sessionSuspensions.isEmpty
        sessionSuspensions.insert(reason)
        guard firstSuspension else { return }
        let wasUnlocked = !isLocked
        if wasUnlocked && preferences.clearHistoryOnSessionLock {
            lock()
            resumeAfterSession = preferences.storageMode == .memory
            return
        }
        resumeAfterSession = wasUnlocked
        lockEpoch += 1
        storageTask?.cancel()
        runningSync?.cancel()
        monitor?.stop()
        isCapturing = false
        clearOwnedClipboard()
        transfers.removeAll()
        PreviewCache.shared.removeAll()
        selectedID = nil
        isLocked = true
    }

    private func resumeSession(from reason: SessionSuspension) {
        guard sessionSuspensions.remove(reason) != nil, sessionSuspensions.isEmpty else { return }
        let shouldResume = resumeAfterSession
        resumeAfterSession = false
        guard shouldResume else { return }
        isLocked = false
        prune()
        selectedID = snapshot.entries.first?.id
        configureMonitor()
    }

    private func observeSession(workspace: NotificationCenter, screen: NotificationCenter) {
        let pairs: [(NotificationCenter, Notification.Name, Notification.Name, SessionSuspension)] = [
            (workspace, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, .systemSleep),
            (workspace, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .displaySleep),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession),
            (screen, .init("com.apple.screenIsLocked"), .init("com.apple.screenIsUnlocked"), .screenLock)
        ]
        for (center, pause, resume, reason) in pairs {
            let pauseObserver = center.addObserver(forName: pause, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendSession(for: reason) }
            }
            let resumeObserver = center.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeSession(from: reason) }
            }
            observers.append((center, pauseObserver))
            observers.append((center, resumeObserver))
        }
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
    static var context: LAContext?
    static func authenticate() async throws {
        let context = LAContext()
        var reason: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &reason) else {
            throw reason ?? NSError(domain: "CopyTaste", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Set a Mac login password to use encrypted storage."])
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open CopyTaste encrypted history")
        self.context = context
    }
}

@MainActor enum SessionState {
    static func isActive() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true,
              session["CGSSessionScreenIsLocked"] as? Bool != true,
              NSWorkspace.shared.frontmostApplication != nil else { return false }
        return !IsSecureEventInputEnabled()
    }
}

private extension RejectionReason {
    var captureMessage: String {
        switch self {
        case .sourceChanged: "A copy was skipped during an app switch. Copy it again after switching."
        case .secret, .concealed: "A private or potentially sensitive copy was skipped."
        case .tooLarge: "A copy exceeded the capture size limit."
        case .excludedApplication: "A copy from an excluded app was skipped."
        case .secureInput: "Capture paused for a copy while secure input was active."
        case .unknownSource: "A copy with an unknown source was skipped."
        case .unsupported, .empty: "An empty or unsupported copy was skipped."
        case .permissionRequired: "Clipboard access needs approval. Set Paste from Other Apps to Allow in System Settings."
        case .selfWrite: ""
        }
    }
}
