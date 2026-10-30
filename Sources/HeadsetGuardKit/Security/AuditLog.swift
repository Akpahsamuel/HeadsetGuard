import Foundation

public struct AuditLog {
    public let fileURL: URL
    public let limit: Int

    public init(fileURL: URL, limit: Int = 100) {
        self.fileURL = fileURL
        self.limit = limit
    }

    public func append(event: String, details: String, type: String) {
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: logs, options: .prettyPrinted) {
            try? data.write(to: fileURL, options: .atomic)
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
