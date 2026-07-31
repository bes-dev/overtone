import Carbon
import SwiftUI

@main
struct OvertoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
                .frame(width: 390, height: 620)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuIcon: String {
        if state.serverStatus == .failed { return "exclamationmark.triangle" }
        if state.isPaused { return "pause.circle.fill" }
        return state.isSpeaking ? "waveform.circle.fill" : "waveform.circle"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// An accessory app never receives `application(_:open:)`, so take the Apple Event itself.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutdown()
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        // A hand-typed URL can carry unescaped Cyrillic; escape it before parsing.
        let escaped = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        guard let components = URLComponents(string: URL(string: raw) == nil ? escaped : raw),
              components.scheme == "overtone" || components.scheme == "supertonic" else { return }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let text = value("text") else { return }
        AppState.shared.text = text
        AppState.shared.speak(text: text, voice: value("voice"), language: value("language"))
    }
}
