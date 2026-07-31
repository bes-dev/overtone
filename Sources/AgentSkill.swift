import Foundation

/// The agent-facing contract, shipped as `SKILL.md` inside the bundle so the document,
/// the pasteboard button and the `/skill` endpoint all read the same source.
enum AgentSkill {
    static var markdown: String? {
        guard let url = Bundle.main.url(forResource: "SKILL", withExtension: "md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
