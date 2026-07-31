import Foundation

final class BackendController {
    private var process: Process?
    private var logPipe: Pipe?
    private var stoppingIntentionally = false

    var isRunning: Bool { process?.isRunning ?? false }

    func start(
        binary: String,
        modelDirectory: String,
        voicesDirectory: String,
        port: UInt16,
        staticCoreML: Bool,
        onLog: @escaping (String) -> Void,
        onExit: @escaping (Int32) -> Void
    ) throws {
        stop()
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw NSError(domain: "Overtone", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Server binary is not executable: \(binary)"
            ])
        }
        guard FileManager.default.fileExists(atPath: "\(modelDirectory)/tts.json") else {
            throw NSError(domain: "Overtone", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Invalid ONNX directory: \(modelDirectory)"
            ])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var arguments = [
            "--host", "127.0.0.1",
            "--port", String(port),
            "--model-dir", modelDirectory,
            "--voices", voicesDirectory,
            "--execution-provider", "coreml",
        ]
        if staticCoreML {
            let cache = Self.cacheDirectory()
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            arguments += ["--coreml-static-buckets", "--coreml-cache-dir", cache.path]
        }
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") { onLog(String(line)) }
        }
        process.terminationHandler = { [weak self] finished in
            guard let self, !self.stoppingIntentionally else { return }
            self.logPipe?.fileHandleForReading.readabilityHandler = nil
            onExit(finished.terminationStatus)
        }
        stoppingIntentionally = false
        try process.run()
        self.process = process
        logPipe = pipe
    }

    /// Terminates the server and waits for it, so quitting never leaves the port held.
    func stop() {
        stoppingIntentionally = true
        logPipe?.fileHandleForReading.readabilityHandler = nil
        logPipe = nil
        defer { self.process = nil }
        guard let process, process.isRunning else { return }
        process.terminate()
        var waited = 0
        while process.isRunning, waited < 100 {
            usleep(20_000)
            waited += 1
        }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// Terminates a server this app did not spawn — left behind by a crash or an older
    /// build — so a restart really does apply new settings. Only ever our own binary.
    func reclaim(port: UInt16, binary: String) {
        let ours = listeners(on: port).filter { executable(of: $0) == binary }
        guard !ours.isEmpty else { return }
        ours.forEach { kill($0, SIGTERM) }
        var waited = 0
        while !listeners(on: port).isEmpty, waited < 10 {
            usleep(200_000)
            waited += 1
        }
    }

    private func listeners(on port: UInt16) -> [pid_t] {
        shell("/usr/sbin/lsof", ["-ti", "tcp:\(port)", "-sTCP:LISTEN"])
            .split(separator: "\n")
            .compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func executable(of pid: pid_t) -> String {
        shell("/bin/ps", ["-p", "\(pid)", "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shell(_ launchPath: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: output, encoding: .utf8) ?? ""
    }

    func isHealthy(port: UInt16) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/healthz") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Overtone/CoreML", directoryHint: .isDirectory)
    }
}

