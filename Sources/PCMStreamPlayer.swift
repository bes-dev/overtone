import AVFoundation
import Foundation

/// Plays a stream of little-endian Int16 PCM at 44.1 kHz. Drops the silence every
/// synthesized utterance starts with, and re-schedules unplayed audio when the output
/// device changes underneath the engine.
final class PCMStreamPlayer {
    struct Progress {
        let elapsed: TimeInterval
        let buffered: TimeInterval
    }

    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "ai.overtone.pcm-player")
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: PCMStreamPlayer.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private var carry = Data()
    private var lead = Data()
    private var trimmingLead = true
    private var queued: [AVAudioPCMBuffer] = []
    private var session = 0
    private var completedFrames: AVAudioFramePosition = 0
    private var sessionStart: AVAudioFramePosition = 0
    private var bufferedFrames: AVAudioFramePosition = 0
    private var streamFinished = false
    private var paused = false
    private var frozen: AVAudioFramePosition?
    /// The node's sample clock restarts at zero after `stop()`, but not after `pause()`.
    private var clockZeroed = true
    private var onDrained: (() -> Void)?

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var progress: Progress {
        queue.sync {
            let frames = frozen ?? currentFrames()
            return Progress(
                elapsed: Double(min(frames, bufferedFrames)) / Self.sampleRate,
                buffered: Double(bufferedFrames) / Self.sampleRate
            )
        }
    }

    /// Frames heard so far. The node's clock is exact while it runs; completed buffers
    /// are the floor it can never fall below, which is what a paused node reports.
    private func currentFrames() -> AVAudioFramePosition {
        guard let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render) else {
            return completedFrames
        }
        return max(completedFrames, sessionStart + time.sampleTime)
    }

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try? engine.start()
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in self?.restartAfterConfigurationChange() }
    }

    func beginStream() {
        queue.async { [weak self] in
            guard let self else { return }
            self.node.stop()
            self.resetStream()
        }
    }

    func enqueue(_ incoming: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            var data = self.carry
            data.append(incoming)
            let byteCount = data.count - (data.count % MemoryLayout<Int16>.size)
            guard byteCount > 0 else {
                self.carry = data
                return
            }
            self.carry = Data(data.dropFirst(byteCount))
            let samples = Data(data.prefix(byteCount))
            guard self.trimmingLead else {
                self.schedule(samples)
                return
            }
            self.lead.append(samples)
            if let onset = SilenceTrim.onsetOffset(self.lead) {
                self.trimmingLead = false
                self.schedule(Data(self.lead.dropFirst(onset)))
                self.lead = Data()
            } else if self.lead.count >= SilenceTrim.maxLeadFrames * MemoryLayout<Int16>.size {
                self.trimmingLead = false
                self.schedule(self.lead)
                self.lead = Data()
            }
        }
    }

    func finish(onDrained: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.lead.isEmpty {
                self.schedule(self.lead)
                self.lead = Data()
            }
            self.trimmingLead = false
            self.streamFinished = true
            self.onDrained = onDrained
            self.completeIfDrained()
        }
    }

    func setPaused(_ value: Bool) {
        queue.async { [weak self] in
            guard let self, self.paused != value else { return }
            self.paused = value
            if value {
                self.frozen = self.currentFrames()
                self.node.pause()
            } else {
                self.frozen = nil
                if !self.queued.isEmpty { self.node.play() }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.node.stop()
            self?.resetStream()
        }
    }

    private func schedule(_ samples: Data) {
        let frames = AVAudioFrameCount(samples.count / MemoryLayout<Int16>.size)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.int16ChannelData?[0] else { return }
        buffer.frameLength = frames
        samples.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress else { return }
            memcpy(channel, sourceBase, samples.count)
        }
        bufferedFrames += AVAudioFramePosition(frames)
        play(buffer)
    }

    /// Hands a buffer to the node and remembers it until it has actually been heard,
    /// so a device change can put it back in the queue.
    private func play(_ buffer: AVAudioPCMBuffer) {
        if !engine.isRunning { try? engine.start() }
        queued.append(buffer)
        let generation = session
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.queue.async {
                guard let self, generation == self.session else { return }
                self.completedFrames += AVAudioFramePosition(buffer.frameLength)
                if !self.queued.isEmpty { self.queued.removeFirst() }
                self.completeIfDrained()
            }
        }
        if !node.isPlaying && !paused {
            if clockZeroed {
                sessionStart = completedFrames
                clockZeroed = false
            }
            node.play()
        }
    }

    private func restartAfterConfigurationChange() {
        queue.async { [weak self] in
            guard let self else { return }
            let replay = self.queued
            self.session += 1
            self.queued = []
            self.node.stop()
            self.clockZeroed = true
            self.engine.connect(self.node, to: self.engine.mainMixerNode, format: self.format)
            try? self.engine.start()
            replay.forEach(self.play)
        }
    }

    private func resetStream() {
        session += 1
        carry.removeAll(keepingCapacity: true)
        lead.removeAll(keepingCapacity: true)
        queued.removeAll()
        trimmingLead = true
        paused = false
        frozen = nil
        clockZeroed = true
        completedFrames = 0
        sessionStart = 0
        bufferedFrames = 0
        streamFinished = false
        onDrained = nil
    }

    private func completeIfDrained() {
        guard streamFinished, queued.isEmpty else { return }
        streamFinished = false
        let completion = onDrained
        onDrained = nil
        completion?()
    }
}
