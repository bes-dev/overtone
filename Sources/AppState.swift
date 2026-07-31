import AppKit
import Carbon.HIToolbox
import Foundation
import ServiceManagement

enum ServerStatus {
    case stopped
    case starting
    case ready
    case failed
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var text = ""
    @Published var voice: String { didSet { defaults.set(voice, forKey: "voice") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var totalSteps: Int { didSet { defaults.set(totalSteps, forKey: "totalSteps") } }
    @Published var speed: Double { didSet { defaults.set(speed, forKey: "speed") } }
    @Published var maxChunkLength: Int { didSet { defaults.set(maxChunkLength, forKey: "chunkChars") } }
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: "volume")
            player.volume = Float(volume)
        }
    }
    @Published var useStaticCoreML: Bool {
        didSet {
            defaults.set(useStaticCoreML, forKey: "useStaticCoreML")
            restartServer()
        }
    }
    @Published var hotKeysEnabled: Bool {
        didSet {
            defaults.set(hotKeysEnabled, forKey: "hotKeysEnabled")
            applyHotKeys()
        }
    }
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var serverStatus: ServerStatus = .stopped
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var buffered: TimeInterval = 0
    @Published var lastError: String?

    let voices = (1...5).map { "M\($0)" } + (1...5).map { "F\($0)" }
    let languages = ["ru", "en", "uk", "de", "fr", "es", "it", "pt", "pl", "ja", "ko", "na"]
    let controlPort: UInt16 = 7789
    let speakHotKeyLabel = "⌥⌘S"
    let stopHotKeyLabel = "⌥⌘."

    var statusJSON: String {
        let payload: [String: Any] = [
            "status": isSpeaking ? (isPaused ? "paused" : "speaking") : "idle",
            "server": serverStatus.apiName,
            "elapsed": NSDecimalNumber(string: String(format: "%.2f", elapsed)),
            "buffered": NSDecimalNumber(string: String(format: "%.2f", buffered)),
            "error": lastError ?? NSNull(),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return #"{"status":"unknown"}"# }
        return json
    }

    private let backendPort: UInt16 = 7788
    private let backend = BackendController()
    private let player = PCMStreamPlayer()
    private let hotKeys = GlobalHotKeys()
    private var speechRequest: StreamingSpeechRequest?
    private var currentRequestID = UUID()
    private var controlServer: ControlServer?
    private var progressTimer: Timer?
    private let defaults = UserDefaults.standard

    private var runtimeDirectory: URL {
        Bundle.main.resourceURL!.appending(path: "Runtime", directoryHint: .isDirectory)
    }

    private var serverBinary: String {
        runtimeDirectory.appending(path: "supertonic-server").path
    }

    private init() {
        let defaults = UserDefaults.standard
        voice = defaults.string(forKey: "voice") ?? "M1"
        language = defaults.string(forKey: "language") ?? "ru"
        totalSteps = defaults.object(forKey: "totalSteps") as? Int ?? 8
        speed = defaults.object(forKey: "speed") as? Double ?? 1.05
        maxChunkLength = defaults.object(forKey: "chunkChars") as? Int ?? 300
        volume = defaults.object(forKey: "volume") as? Double ?? 1
        useStaticCoreML = defaults.bool(forKey: "useStaticCoreML")
        hotKeysEnabled = defaults.object(forKey: "hotKeysEnabled") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled

        player.volume = Float(volume)
        AppBridge.shared.state = self
        Task {
            // The control port allows endpoint reuse, so a second copy would silently
            // share it and both menu bar icons would answer. Ask first instead.
            guard await !anotherInstanceIsRunning() else { return quitAsDuplicate() }
            applyHotKeys()
            startControlServer()
            await startBackend()
        }
    }

    private func anotherInstanceIsRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(controlPort)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8)?.contains("\"ok\"") == true
    }

    /// Two menu bar icons answering the same hotkeys is worse than no second icon at all.
    private func quitAsDuplicate() {
        FileHandle.standardError.write(Data("Overtone is already running; this copy is quitting.\n".utf8))
        NSApp.terminate(nil)
    }

    func speak(
        text overrideText: String? = nil,
        voice overrideVoice: String? = nil,
        language overrideLanguage: String? = nil,
        speed overrideSpeed: Double? = nil,
        steps overrideSteps: Int? = nil,
        maxChunkLength overrideMaxChunkLength: Int? = nil
    ) {
        let value = SpeechText.normalized(overrideText ?? text)
        guard !value.isEmpty else { return }
        stop()
        let requestID = UUID()
        currentRequestID = requestID
        lastError = nil

        Task {
            if serverStatus != .ready {
                await startBackend()
            }
            guard serverStatus == .ready, currentRequestID == requestID else { return }

            let body = SpeechRequestBody(
                input: value,
                voice: overrideVoice ?? voice,
                responseFormat: "pcm",
                speed: overrideSpeed ?? speed,
                language: overrideLanguage ?? language,
                totalStep: overrideSteps ?? totalSteps,
                maxChunkLength: overrideMaxChunkLength ?? maxChunkLength,
                silenceMs: 0
            )
            guard let url = URL(string: "http://127.0.0.1:\(backendPort)/v1/audio/speech") else { return }
            startProgressUpdates()
            isSpeaking = true
            player.beginStream()
            speechRequest = StreamingSpeechRequest(
                url: url,
                body: body,
                onData: { [weak self] data in self?.player.enqueue(data) },
                onCompletion: { [weak self] error in
                    Task { @MainActor in self?.finishRequest(requestID, error: error) }
                }
            )
            speechRequest?.start()
        }
    }

    func stop() {
        currentRequestID = UUID()
        speechRequest?.cancel()
        speechRequest = nil
        player.stop()
        stopProgressUpdates()
        isSpeaking = false
        isPaused = false
        elapsed = 0
        buffered = 0
    }

    func togglePause() {
        guard isSpeaking else { return }
        isPaused.toggle()
        player.setPaused(isPaused)
    }

    func readClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Clipboard has no text"
            return
        }
        text = value
        speak()
    }

    /// Puts the agent-facing SKILL.md on the pasteboard, so a coding assistant can be
    /// handed the whole contract for speaking through this app in one paste.
    func copyAgentSkill() -> Bool {
        guard let markdown = AgentSkill.markdown else {
            lastError = "SKILL.md is missing from the app bundle"
            return false
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func restartServer() {
        stop()
        backend.stop()
        backend.reclaim(port: backendPort, binary: serverBinary)
        serverStatus = .stopped
        Task { await startBackend() }
    }

    func shutdown() {
        stop()
        controlServer?.stop()
        hotKeys.unregisterAll()
        backend.stop()
    }

    private func finishRequest(_ requestID: UUID, error: Error?) {
        guard currentRequestID == requestID else { return }
        speechRequest = nil
        if let error {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            stopProgressUpdates()
            isSpeaking = false
            lastError = error.localizedDescription
            return
        }
        player.finish { [weak self] in
            Task { @MainActor in
                guard let self, self.currentRequestID == requestID else { return }
                self.updateProgress()
                self.stopProgressUpdates()
                self.isSpeaking = false
                self.isPaused = false
            }
        }
    }

    private func startProgressUpdates() {
        progressTimer?.invalidate()
        elapsed = 0
        buffered = 0
        // .common keeps it ticking while the menu popover tracks events.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateProgress() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        let progress = player.progress
        elapsed = progress.elapsed
        buffered = progress.buffered
    }

    private func applyHotKeys() {
        hotKeys.unregisterAll()
        guard hotKeysEnabled else { return }
        let modifiers = optionKey | cmdKey
        let registered = hotKeys.register(keyCode: kVK_ANSI_S, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.readClipboard() }
        } && hotKeys.register(keyCode: kVK_ANSI_Period, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.stop() }
        }
        if !registered {
            lastError = "Could not register \(speakHotKeyLabel) — another app owns it"
        }
    }

    private func startBackend() async {
        if serverStatus == .starting { return }
        if await backend.isHealthy(port: backendPort) {
            serverStatus = .ready
            return
        }
        serverStatus = .starting
        lastError = nil
        do {
            try backend.start(
                binary: serverBinary,
                modelDirectory: runtimeDirectory.appending(path: "onnx", directoryHint: .isDirectory).path,
                voicesDirectory: runtimeDirectory.appending(path: "voice_styles", directoryHint: .isDirectory).path,
                port: backendPort,
                staticCoreML: useStaticCoreML,
                onLog: { [weak self] line in
                    guard line.lowercased().contains("error") || line.lowercased().contains("panic") else { return }
                    Task { @MainActor in self?.lastError = line }
                },
                onExit: { [weak self] status in
                    Task { @MainActor in
                        guard let self else { return }
                        self.stop()
                        self.serverStatus = .failed
                        self.lastError = "Speech server exited with status \(status)"
                    }
                }
            )
            for _ in 0..<240 {
                if await backend.isHealthy(port: backendPort) {
                    serverStatus = .ready
                    return
                }
                if !backend.isRunning { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            throw NSError(domain: "Overtone", code: 1, userInfo: [
                NSLocalizedDescriptionKey: backend.isRunning
                    ? "Server did not become ready in 24 seconds"
                    : "Server exited during startup"
            ])
        } catch {
            serverStatus = .failed
            lastError = error.localizedDescription
        }
    }

    private func startControlServer() {
        do {
            controlServer = try ControlServer(port: controlPort) { [weak self] request, respond in
                Task { @MainActor in
                    guard let self else { return respond(.notFound) }
                    respond(ControlAPI.handle(request, state: self))
                }
            }
            controlServer?.start { [weak self] error in
                Task { @MainActor in
                    self?.lastError = "Control API: \(error.localizedDescription)"
                }
            }
        } catch {
            lastError = "Control API: \(error.localizedDescription)"
        }
    }
}

extension ServerStatus {
    var apiName: String {
        switch self {
        case .stopped: "stopped"
        case .starting: "starting"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}
