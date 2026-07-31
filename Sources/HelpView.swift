import SwiftUI

/// Everything a new user needs to know, in one panel: what the shortcuts are and how to
/// drive the app from a script. Takes plain values so it renders on its own.
struct HelpView: View {
    let appName: String
    let version: String
    let speakHotKey: String
    let stopHotKey: String
    let controlPort: UInt16

    private var globalShortcuts: [(String, String)] {
        [(speakHotKey, "Speak the clipboard"), (stopHotKey, "Stop")]
    }

    private let windowShortcuts = [
        ("⌘↩", "Speak the text above"),
        ("⌘.", "Stop"),
        ("⌘Q", "Quit"),
    ]

    private let endpoints = [
        ("POST /speak", "text, and optionally voice, language, speed"),
        ("POST /pause", "toggle pause"),
        ("POST /stop", "stop"),
        ("GET /status", "what it is doing right now"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(appName).font(.headline)
                Text(version).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("offline · on-device").font(.caption2).foregroundStyle(.tertiary)
            }
            shortcuts("Anywhere on the Mac", rows: globalShortcuts)
            shortcuts("While this panel is open", rows: windowShortcuts)
            VStack(alignment: .leading, spacing: 6) {
                title("From a script")
                ForEach(endpoints, id: \.0) { path, note in
                    row(Text(path).font(.caption.monospaced()), note: note)
                }
                Text("The sparkles button copies SKILL.md — hand it to a coding agent and it can "
                     + "answer out loud through Overtone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text("http://127.0.0.1:" + String(controlPort) + " · loopback only")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }
            Divider()
            Text("Paste anything — markdown, bullet lists, wrapped paragraphs. It is cleaned up "
                 + "into whole sentences before it is read.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shortcuts(_ heading: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title(heading)
            ForEach(rows, id: \.0) { key, note in
                row(
                    Text(key)
                        .font(.callout.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5)),
                    note: note
                )
            }
        }
    }

    private func row(_ leading: some View, note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            leading.frame(width: 88, alignment: .leading)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
    }
}
