import AppIntents

@MainActor
final class AppBridge {
    static let shared = AppBridge()
    weak var state: AppState?
}

struct SpeakTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak with Overtone"
    static let description = IntentDescription("Read text aloud using the local Overtone voice server.")
    static let openAppWhenRun = false

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Voice", description: "Leave empty to use the current voice") var voice: String?
    @Parameter(title: "Language", description: "Leave empty to use the current language") var language: String?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppBridge.shared.state?.speak(text: text, voice: voice, language: language)
        }
        return .result()
    }
}

struct StopSpeakingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Overtone"
    static let description = IntentDescription("Stop local speech playback immediately.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppBridge.shared.state?.stop() }
        return .result()
    }
}

struct SpeakClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak clipboard with Overtone"
    static let description = IntentDescription("Read whatever is on the clipboard aloud.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppBridge.shared.state?.readClipboard() }
        return .result()
    }
}

struct SpeakSelectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Speak selection with Overtone"
    static let description = IntentDescription("Copy the selected text and read it aloud.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { AppBridge.shared.state?.speakSelection() }
        return .result()
    }
}
