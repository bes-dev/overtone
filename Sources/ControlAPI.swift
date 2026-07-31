import Foundation

struct ControlSpeakRequest: Decodable {
    let text: String
    let voice: String?
    let language: String?
    let speed: Double?
    let totalStep: Int?
    let maxChunkLength: Int?

    enum CodingKeys: String, CodingKey {
        case text, voice, language, speed
        case totalStep = "total_step"
        case maxChunkLength = "max_chunk_length"
    }
}

/// Maps the loopback HTTP surface onto the app. Everything runs on the main actor,
/// so the listener hands work over and answers immediately.
@MainActor
enum ControlAPI {
    static func handle(_ request: ControlServer.Request, state: AppState) -> ControlServer.Response {
        switch (request.method, request.path) {
        case ("POST", "/speak"):
            guard let speak = try? JSONDecoder().decode(ControlSpeakRequest.self, from: request.body) else {
                return .init(status: "400 Bad Request", json: #"{"error":"invalid JSON"}"#)
            }
            guard !speak.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .init(status: "400 Bad Request", json: #"{"error":"text is empty"}"#)
            }
            state.text = speak.text
            state.speak(
                text: speak.text,
                voice: speak.voice,
                language: speak.language,
                speed: speak.speed,
                steps: speak.totalStep,
                maxChunkLength: speak.maxChunkLength
            )
            return .init(status: "202 Accepted", json: #"{"status":"speaking"}"#)
        case ("POST", "/stop"):
            state.stop()
            return .init(status: "200 OK", json: #"{"status":"stopped"}"#)
        case ("POST", "/pause"):
            state.togglePause()
            return .init(status: "200 OK", json: #"{"status":"\#(state.isPaused ? "paused" : "playing")"}"#)
        case ("GET", "/health"):
            return .init(status: "200 OK", json: #"{"status":"ok"}"#)
        case ("GET", "/skill"):
            guard let markdown = AgentSkill.markdown else {
                return .init(status: "404 Not Found", json: #"{"error":"SKILL.md is missing"}"#)
            }
            return .init(status: "200 OK", json: markdown, contentType: "text/markdown; charset=utf-8")
        case ("GET", "/status"):
            return .init(status: "200 OK", json: state.statusJSON)
        default:
            return .notFound
        }
    }
}
