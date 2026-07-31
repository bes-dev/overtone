import XCTest

final class SilenceTrimTests: XCTestCase {
    private func pcm(_ samples: [Int16]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    func testAllSilenceHasNoOnset() {
        XCTAssertNil(SilenceTrim.onsetOffset(pcm(Array(repeating: 0, count: 5_000))))
    }

    func testQuietNoiseIsStillSilence() {
        let noise = (0..<5_000).map { Int16($0 % 2 == 0 ? SilenceTrim.level : -SilenceTrim.level) }
        XCTAssertNil(SilenceTrim.onsetOffset(pcm(noise)))
    }

    func testOnsetKeepsPreroll() {
        let silence = Array(repeating: Int16(0), count: 10_000)
        let offset = SilenceTrim.onsetOffset(pcm(silence + [9_000]))
        XCTAssertEqual(offset, (10_000 - SilenceTrim.prerollFrames) * 2)
    }

    func testOnsetNearStartIsNotNegative() {
        XCTAssertEqual(SilenceTrim.onsetOffset(pcm([0, 0, 9_000])), 0)
    }

    func testLoudFromTheFirstSample() {
        XCTAssertEqual(SilenceTrim.onsetOffset(pcm([-9_000, 0, 0])), 0)
    }

    func testEmptyInput() {
        XCTAssertNil(SilenceTrim.onsetOffset(Data()))
    }
}
