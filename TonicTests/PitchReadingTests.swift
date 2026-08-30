import XCTest
@testable import Tone_Tuner

final class PitchReadingTests: XCTestCase {
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

    func testNegativeMIDINoteUsesFloorDivisionForOctave() {
        let midiMinusOneFrequency = 440 * pow(2, (-1.0 - 69) / 12)
        XCTAssertEqual(PitchReading(frequency: midiMinusOneFrequency, referencePitch: 440).noteName, "B-2")
    }
}
