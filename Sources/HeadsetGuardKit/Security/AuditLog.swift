import Foundation

public struct AuditLog {
    private static let writeLock = NSLock()

    public let fileURL: URL
    public let limit: Int

    public init(fileURL: URL, limit: Int = 500) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func append(event: String, details: String, type: String) {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())

        let entry: [String: String] = [
            "timestamp": timestamp,
            "event": event,
            "details": details,
            "type": type
        ]

        var logs = recent()
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

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
