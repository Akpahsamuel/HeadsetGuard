import Foundation
import CryptoKit

public struct AuditLog {
    public enum Integrity: Equatable {
        /// No key configured, or no signed entries yet; nothing to verify.
        case unsigned
        case valid
        /// Index into `recent()` (newest first) of the first entry that fails verification.
        case broken(at: Int)
    }

    private static let writeLock = NSLock()

    public let fileURL: URL
    public let limit: Int
    private let hmacKey: Data?

    /// With an `hmacKey`, each entry carries `prev` (the hash of the entry before it) and `hash`
    /// (HMAC over prev + fields), so edits, deletions and forged entries show up in `verify()`.
    public init(fileURL: URL, limit: Int = 500, hmacKey: Data? = nil) {
        self.fileURL = fileURL
        self.limit = limit
        self.hmacKey = hmacKey
    }

    private func entryHash(prev: String, timestamp: String, event: String, details: String, type: String) -> String? {
        guard let key = hmacKey else { return nil }
        var message = Data()
        for part in [prev, timestamp, event, details, type] {
            // Length-prefix every field so field boundaries can't be shifted.
            let bytes = Data(part.utf8)
            message.append(contentsOf: withUnsafeBytes(of: UInt32(bytes.count).bigEndian, Array.init))
            message.append(bytes)
        }
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    public func append(event: String, details: String, type: String) {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        var entry: [String: String] = [
            "timestamp": timestamp,
            "event": event,
            "details": details,
            "type": type
        ]

        var logs = recent()
        if hmacKey != nil {
            let prev = logs.first?["hash"] ?? ""
            entry["prev"] = prev
            entry["hash"] = entryHash(prev: prev, timestamp: timestamp, event: event, details: details, type: type)
        }
        logs.insert(entry, at: 0) // newest first
        if logs.count > limit {
            logs = Array(logs.prefix(limit))
        }

        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if let data = try? JSONSerialization.data(withJSONObject: logs, options: .prettyPrinted) {
            try? data.write(to: fileURL, options: .atomic)
            // Owner-only: the log records device names and authentication events.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    public func recent() -> [[String: String]] {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        return json
    }

    /// Checks the HMAC chain. Entries written before signing was enabled (no `hash`) are
    /// tolerated only if they are all older than every signed entry.
    public func verify() -> Integrity {
        guard hmacKey != nil else { return .unsigned }
        let logs = recent()
        guard logs.contains(where: { $0["hash"] != nil }) else { return .unsigned }

        var sawSigned = false
        for index in stride(from: logs.count - 1, through: 0, by: -1) {   // oldest -> newest
            let e = logs[index]
            guard let hash = e["hash"], let prev = e["prev"] else {
                if sawSigned { return .broken(at: index) }   // signature stripped from a newer entry
                continue
            }
            let expected = entryHash(prev: prev,
                                     timestamp: e["timestamp"] ?? "",
                                     event: e["event"] ?? "",
                                     details: e["details"] ?? "",
                                     type: e["type"] ?? "")
            if expected != hash { return .broken(at: index) }

            // Link to the next-older entry (the oldest retained entry's predecessor was trimmed).
            if index + 1 < logs.count, let olderHash = logs[index + 1]["hash"], prev != olderHash {
                return .broken(at: index)
            }
            sawSigned = true
        }
        return .valid
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
