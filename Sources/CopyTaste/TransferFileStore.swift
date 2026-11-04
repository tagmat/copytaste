import Foundation
import CopyTasteCore

@MainActor
final class TransferFileStore {
    private var folders: [UUID: URL] = [:]
    private var cleanup: [UUID: Task<Void, Never>] = [:]

    func materialize(_ entry: ClipEntry) throws -> URL {
        guard entry.kind == .file, let data = entry.fileData, data.count <= CapturePolicy.maxFileBytes,
              let original = entry.fileName, !CapturePolicy.isProtectedFileName(original) else { throw VaultError.unsafePath }
        let name = (original as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != ".." else { throw VaultError.unsafePath }
        let id = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("copytaste-transfer-" + id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let file = folder.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            var mutable = file
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try mutable.setResourceValues(values)
            folders[id] = folder
            cleanup[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.remove(id)
            }
            return file
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    private func remove(_ id: UUID) {
        if let folder = folders.removeValue(forKey: id) { try? FileManager.default.removeItem(at: folder) }
        cleanup.removeValue(forKey: id)?.cancel()
    }

    func removeAll() { for id in Array(folders.keys) { remove(id) } }
}
