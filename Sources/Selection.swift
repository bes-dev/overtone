import AppKit
import Carbon.HIToolbox

/// Reads the frontmost app's selection by synthesizing ⌘C — macOS offers no way to ask
/// another app for its selected text without driving the keyboard.
enum Selection {
    /// Posting keystrokes into another app is an accessibility privilege.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that offers to open the Accessibility list.
    static func requestTrust() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    /// The copied selection, or `nil` when nothing landed on the pasteboard in time —
    /// no selection, or an app that does not answer ⌘C.
    static func copy() async -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        postCommandC()
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            guard pasteboard.changeCount != before else { continue }
            return pasteboard.string(forType: .string)
        }
        return nil
    }

    private static func postCommandC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_C),
                keyDown: isDown
            )
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
