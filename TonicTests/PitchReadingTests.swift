import XCTest
@testable import Tonic

final class PitchReadingTests: XCTestCase {
    func testTapTempoUsesAverageOfRecentIntervals() {
        var tapTempo = TapTempoAverager()
        XCTAssertNil(tapTempo.registerTap(at: 0))
        XCTAssertEqual(tapTempo.registerTap(at: 0.5), 120)
        XCTAssertEqual(tapTempo.registerTap(at: 1.1), 109)
        XCTAssertEqual(tapTempo.registerTap(at: 1.6), 113)
    }

    func testTapTempoStartsANewSequenceAfterTimeout() {
        var tapTempo = TapTempoAverager()
        XCTAssertNil(tapTempo.registerTap(at: 0))
        XCTAssertEqual(tapTempo.registerTap(at: 0.5), 120)
        XCTAssertNil(tapTempo.registerTap(at: 2.5))
        XCTAssertEqual(tapTempo.registerTap(at: 3.0), 120)
    }

    func testReferencePitchesProduceA4() {
        for reference in [432.0, 440.0, 442.0] {
            let reading = PitchReading(frequency: reference, referencePitch: reference)
            XCTAssertEqual(reading.noteName, "A4")
            XCTAssertEqual(reading.cents, 0, accuracy: 0.0001)
            XCTAssertTrue(reading.isInTune)
        }
    }

    func testInTuneBoundaryIsFiveCents() {
        let plusFive = 440 * pow(2, 5.0 / 1_200)
        let outside = 440 * pow(2, 5.1 / 1_200)
        XCTAssertTrue(PitchReading(frequency: plusFive, referencePitch: 440).isInTune)
        XCTAssertFalse(PitchReading(frequency: outside, referencePitch: 440).isInTune)
    }

    func testNoteNamesAroundA4() {
        XCTAssertEqual(PitchReading(frequency: 261.625565, referencePitch: 440).noteName, "C4")
        XCTAssertEqual(PitchReading(frequency: 466.163762, referencePitch: 440).noteName, "A#4")
    }

    func testPitchReadingRespectsNamingAndAccidentalPreferences() {
        let reading = PitchReading(frequency: 466.163762, referencePitch: 440)
        XCTAssertEqual(reading.noteName(style: .letter, accidentals: .flat), "B♭4")
        XCTAssertEqual(reading.noteName(style: .solfege, accidentals: .sharp), "La♯4")
        XCTAssertEqual(reading.noteName(style: .solfege, accidentals: .flat), "Si♭4")
    }

    func testNegativeMIDINoteUsesFloorDivisionForOctave() {
        let midiMinusOneFrequency = 440 * pow(2, (-1.0 - 69) / 12)
        XCTAssertEqual(PitchReading(frequency: midiMinusOneFrequency, referencePitch: 440).noteName, "B-2")
    }

    func testPitchDetectorFinds440HzFundamental() {
        let sampleRate = 44_100.0
        let samples = (0..<1_536).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate))
        }
        let result = samples.withUnsafeBufferPointer {
            PitchDetector.estimatePitch(samples: $0.baseAddress!, count: $0.count, sampleRate: sampleRate)
        }
        XCTAssertEqual(result.frequency ?? 0, 440, accuracy: 2)
    }

    func testPitchDetectorFindsQuiet440HzFundamental() {
        let sampleRate = 44_100.0
        let samples = (0..<1_536).map { index in
            Float(0.001 * sin(2 * Double.pi * 440 * Double(index) / sampleRate))
        }
        let result = samples.withUnsafeBufferPointer {
            PitchDetector.estimatePitch(samples: $0.baseAddress!, count: $0.count, sampleRate: sampleRate)
        }
        XCTAssertEqual(result.frequency ?? 0, 440, accuracy: 2)
    }

    func testPitchDetectorFindsLowViolinFundamentalInsteadOfHarmonic() {
        let sampleRate = 44_100.0
        let samples = (0..<1_536).map { index in
            let phase = 2 * Double.pi * Double(index) / sampleRate
            return Float(sin(2 * Double.pi * 196 * Double(index) / sampleRate) + 0.65 * sin(3 * phase * 196))
        }
        let result = samples.withUnsafeBufferPointer {
            PitchDetector.estimatePitch(samples: $0.baseAddress!, count: $0.count, sampleRate: sampleRate)
        }
        XCTAssertEqual(result.frequency ?? 0, 196, accuracy: 3)
    }
}
