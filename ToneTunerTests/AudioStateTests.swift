import XCTest
@testable import Tone_Tuner

final class AudioStateTests: XCTestCase {
    func testOnlyStartingAndRunningAreActive() {
        XCTAssertFalse(AudioEngineState.idle.isActive)
        XCTAssertTrue(AudioEngineState.starting.isActive)
        XCTAssertTrue(AudioEngineState.running.isActive)
        XCTAssertFalse(AudioEngineState.interrupted.isActive)
        XCTAssertFalse(AudioEngineState.failed(.microphoneUnavailable).isActive)
        XCTAssertFalse(AudioEngineState.failed(.engineStartFailed).isActive)
        XCTAssertFalse(AudioEngineState.stopped.isActive)
    }

    func testErrorsHaveUserFacingMessages() {
        XCTAssertFalse(AudioEngineError.microphonePermissionDenied.message.isEmpty)
        XCTAssertFalse(AudioEngineError.microphoneUnavailable.message.isEmpty)
        XCTAssertFalse(AudioEngineError.audioSessionUnavailable.message.isEmpty)
        XCTAssertFalse(AudioEngineError.engineStartFailed.message.isEmpty)
    }

    func testSuccessfulLifecycle() {
        var machine = AudioEngineStateMachine()
        machine.send(.begin)
        XCTAssertEqual(machine.state, .starting)
        machine.send(.started)
        XCTAssertEqual(machine.state, .running)
        machine.send(.stopped)
        XCTAssertEqual(machine.state, .stopped)
    }

    func testPermissionDenialAndRetry() {
        var machine = AudioEngineStateMachine()
        machine.send(.failed(.microphonePermissionDenied))
        XCTAssertEqual(machine.state, .failed(.microphonePermissionDenied))
        machine.send(.begin)
        machine.send(.started)
        XCTAssertEqual(machine.state, .running)
    }

    func testEngineFailureAndRetry() {
        var machine = AudioEngineStateMachine()
        machine.send(.begin)
        machine.send(.failed(.engineStartFailed))
        XCTAssertEqual(machine.state, .failed(.engineStartFailed))
        machine.send(.begin)
        machine.send(.started)
        XCTAssertEqual(machine.state, .running)
    }

    func testInterruptionRecoveryAndStop() {
        var machine = AudioEngineStateMachine()
        machine.send(.begin)
        machine.send(.started)
        machine.send(.interrupted)
        XCTAssertEqual(machine.state, .interrupted)
        machine.send(.begin)
        machine.send(.started)
        XCTAssertEqual(machine.state, .running)
        machine.send(.stopped)
        XCTAssertEqual(machine.state, .stopped)
    }

    func testInvalidStartedEventIsIgnored() {
        var machine = AudioEngineStateMachine()
        machine.send(.started)
        XCTAssertEqual(machine.state, .idle)
    }

    func testInterruptionBeforeRunningIsIgnored() {
        var machine = AudioEngineStateMachine()
        machine.send(.interrupted)
        XCTAssertEqual(machine.state, .idle)
    }
}
