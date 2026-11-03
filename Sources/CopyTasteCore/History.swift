import Foundation

public enum History {
    public static let maximumVaultBytes = 24 * 1_024 * 1_024

    public static func inserting(_ entry: ClipEntry, into snapshot: VaultSnapshot,
                                 preferences: Preferences, now: Date = Date()) -> VaultSnapshot {
        var result = snapshot
        if let index = result.entries.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            var existing = result.entries.remove(at: index)
            existing.createdAt = entry.createdAt
            existing.modifiedAt = entry.createdAt
            existing.sourceName = entry.sourceName
            existing.sourceBundleID = entry.sourceBundleID
            result.entries.insert(existing, at: 0)
        } else {
            result.entries.insert(entry, at: 0)
        }
        return pruned(result, preferences: preferences, now: now)
    }

    public static func pruned(_ snapshot: VaultSnapshot, preferences: Preferences,
                              now: Date = Date()) -> VaultSnapshot {
        var result = snapshot
        let cutoff = now.addingTimeInterval(-Double(max(1, preferences.retentionDays)) * 86_400)
        // Retention applies to pinned entries too. A pin never overrides a privacy boundary.
        result.entries.removeAll { $0.createdAt < cutoff }
        result.entries.sort { $0.createdAt > $1.createdAt }
        let limit = min(1_000, max(1, preferences.maximumEntries))
        if result.entries.count > limit { result.entries = Array(result.entries.prefix(limit)) }
        var total = 0
        result.entries = result.entries.filter { entry in
            total += entry.byteCount
            return total <= maximumVaultBytes
        }
        return result
    }

    public static func search(_ entries: [ClipEntry], query: String) -> [ClipEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in
            let haystack = [entry.title, entry.text, entry.sourceName].compactMap { $0 }.joined(separator: " ")
            return words.allSatisfy { haystack.localizedStandardContains($0) }
        }
    }
}
