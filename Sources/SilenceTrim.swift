import Foundation

/// Finds where speech actually starts in a PCM chunk. The model puts roughly half a
/// second of silence in front of every utterance; playing it back is pure latency.
enum SilenceTrim {
    /// Amplitude that counts as speech rather than the silence a chunk starts with.
    static let level = 300
    /// Silence kept in front of the first audible sample, in frames.
    static let prerollFrames = 882
    /// Give up trimming after this much audio so a quiet passage is never swallowed.
    static let maxLeadFrames = 88_200

    /// Byte offset of the first audible sample, minus the preroll. `nil` while all silence.
    static func onsetOffset(_ data: Data) -> Int? {
        let frame = data.withUnsafeBytes { raw -> Int? in
            raw.bindMemory(to: Int16.self).firstIndex { abs(Int($0)) > level }
        }
        guard let frame else { return nil }
        return max(0, frame - prerollFrames) * MemoryLayout<Int16>.size
    }
}
