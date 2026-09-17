import Foundation
import AppKit

struct TopicSummary: Codable, Identifiable {
    var id: String
    var module: String
    var title: String
    var reason: [String]
    var minutes: Int
    var kind: String
}

struct Coverage: Codable {
    var done: Int
    var total: Int
}

struct NextPayload: Codable {
    var generatedAt: String
    var top: TopicSummary?
    var plan: [TopicSummary]
    var planUsedMinutes: Int
    var dailyTarget: Int
    var streak: Int
    var weekMinutes: Int
    var coverage: Coverage
    var openTasks: Int
}

enum FieldnotesAPI {
    /// Same local server FieldNotes' web UI talks to. Override with the
    /// FIELDNOTES_URL environment variable to point at a different instance
    /// (e.g. a deployed Cloudflare Worker) once that's wired up.
    static var baseURL: String {
        ProcessInfo.processInfo.environment["FIELDNOTES_URL"] ?? "http://127.0.0.1:8765"
    }

    static func fetchNext() async throws -> NextPayload {
        guard let url = URL(string: "\(baseURL)/api/next") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(NextPayload.self, from: data)
    }

    static func openRoute(_ route: String) {
        guard let url = URL(string: "\(baseURL)/#\(route)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The server replaces a progress record's whole JSON payload on save
    /// (no server-side merge — see server.py's ON CONFLICT DO UPDATE), so a
    /// partial update here has to fetch the current record and merge locally
    /// first, exactly like portal.js's `save()` does.
    private static func currentProgress(_ id: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/state") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let progress = obj["progress"] as? [String: Any] else {
            return ["status": "new", "checks": [], "notes": ""]
        }
        return (progress[id] as? [String: Any]) ?? ["status": "new", "checks": [], "notes": ""]
    }

    static func patchProgress(_ id: String, _ patch: [String: Any]) async throws {
        var record = try await currentProgress(id)
        for (key, value) in patch { record[key] = value }
        try await post("/api/save", ["kind": "progress", "id": id, "record": record])
    }

    static func addTask(text: String, date: String) async throws {
        try await post("/api/save", ["kind": "entry", "record": ["type": "task", "text": text, "topic": "", "date": date, "minutes": 0, "resolved": false]])
    }

    private static func post(_ path: String, _ body: [String: Any]) async throws {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 6
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}
