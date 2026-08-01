import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var state: AppState
    @State private var showSettings = false
    @State private var showHelp = false
    @State private var skillCopied = false

    private var canSpeak: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func bundleValue(_ key: String, fallback: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
    }

    var body: some View {
        if showHelp {
            helpPage
        } else {
            mainPage
        }
    }

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpView(
                appName: bundleValue("CFBundleDisplayName", fallback: "Overtone"),
                version: bundleValue("CFBundleShortVersionString", fallback: ""),
                speakHotKey: state.speakHotKeyLabel,
                stopHotKey: state.stopHotKeyLabel,
                controlPort: state.controlPort
            )
            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Done") { showHelp = false }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(14)
    }

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextEditor(text: $state.text)
                .font(.body)
                .frame(minHeight: 130)
                .padding(5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if state.text.isEmpty {
                        Text("Paste or type something to read aloud")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }
                }
            transport
            voiceSettings
            settings
            if let error = state.lastError { errorBanner(error) }
            Divider()
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.serverStatus.color)
                .frame(width: 9, height: 9)
            Text(state.serverStatus.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.serverStatus == .failed {
                Button("Retry", action: state.restartServer)
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
            if canSpeak {
                Text(String(state.text.count) + " chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Button(action: copySkill) {
                Image(systemName: skillCopied ? "checkmark.circle.fill" : "sparkles")
            }
            .buttonStyle(.plain)
            .foregroundStyle(skillCopied ? .green : .secondary)
            .help("Copy SKILL.md — teaches a coding agent to answer through Overtone")

            Button {
                showHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Shortcuts and scripting")
        }
    }

    private func copySkill() {
        guard state.copyAgentSkill() else { return }
        skillCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            skillCopied = false
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    state.speak()
                } label: {
                    Label(state.isSpeaking ? "Restart" : "Speak", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSpeak)

                Button {
                    state.togglePause()
                } label: {
                    Label(state.isPaused ? "Resume" : "Pause",
                          systemImage: state.isPaused ? "play" : "pause.fill")
                }
                .disabled(!state.isSpeaking)

                Button {
                    state.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!state.isSpeaking)

                Spacer()

                Button {
                    state.speakSelection()
                } label: {
                    Label("Selection", systemImage: "text.viewfinder")
                }
                .help("Read the selected text, or the clipboard  ·  \(state.speakHotKeyLabel)")
            }

            if state.isSpeaking {
                HStack(spacing: 8) {
                    ProgressView(value: state.buffered > 0 ? state.elapsed / state.buffered : 0)
                        .progressViewStyle(.linear)
                    Text(timecode)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.isSpeaking)
    }

    private var timecode: String {
        func format(_ value: TimeInterval) -> String {
            String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
        }
        return "\(format(state.elapsed)) / \(format(state.buffered))"
    }

    private var voiceSettings: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Voice")
                Picker("Voice", selection: $state.voice) {
                    ForEach(state.voices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Language")
                Picker("Language", selection: $state.language) {
                    ForEach(state.languages, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Quality")
                Picker("Quality", selection: $state.totalSteps) {
                    Text("Fast · 5").tag(5)
                    Text("Balanced · 8").tag(8)
                    Text("High · 10").tag(10)
                }
                .labelsHidden()
            }
            GridRow {
                Text("Speed")
                slider(value: $state.speed, range: 0.7...2.0, step: 0.05, format: "%.2f")
            }
            GridRow {
                Text("Volume")
                slider(value: $state.volume, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
            }
        }
    }

    private func slider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        scale: Double = 1
    ) -> some View {
        HStack {
            Slider(value: value, in: range, step: step)
            Text(String(format: format, value.wrappedValue * scale))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var settings: some View {
        DisclosureGroup("Settings", isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("Global shortcuts  ·  \(state.speakHotKeyLabel) speak, \(state.stopHotKeyLabel) stop",
                       isOn: $state.hotKeysEnabled)
                if state.needsAccessibility {
                    HStack(spacing: 6) {
                        Text("Reading the selection needs Accessibility")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Grant…", action: state.grantAccessibility)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Toggle("Static MLProgram (may compile new shapes)", isOn: $state.useStaticCoreML)
                Stepper("Chunk limit: " + String(state.maxChunkLength) + " chars",
                        value: $state.maxChunkLength, in: 80...600, step: 20)
                Text("Longer chunks keep whole sentences together; shorter ones start sooner.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Restart speech server", action: state.restartServer)
            }
            .padding(.top, 6)
        }
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer()
            Button {
                state.lastError = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            Text("POST http://127.0.0.1:" + String(state.controlPort) + "/speak")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

extension ServerStatus {
    var label: String {
        switch self {
        case .stopped: "Server stopped"
        case .starting: "Loading model…"
        case .ready: "Ready"
        case .failed: "Server error"
        }
    }

    var color: Color {
        switch self {
        case .stopped: .gray
        case .starting: .orange
        case .ready: .green
        case .failed: .red
        }
    }
}
