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
}
