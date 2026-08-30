import AVFoundation
import Foundation

enum AudioEngineState: Equatable {
    case idle
    case starting
    case running
    case interrupted
    case failed(AudioEngineError)
    case stopped

    var isActive: Bool {
        self == .running || self == .starting
    }
}

enum AudioEngineEvent: Equatable {
    case begin
    case started
    case interrupted
    case failed(AudioEngineError)
    case stopped
}

struct AudioEngineStateMachine {
    private(set) var state: AudioEngineState = .idle

    mutating func send(_ event: AudioEngineEvent) {
        switch event {
        case .begin:
            state = .starting
        case .started where state == .starting:
            state = .running
        case .interrupted where state == .running:
            state = .interrupted
        case .failed(let error):
            state = .failed(error)
        case .stopped:
            state = .stopped
        default:
            break
        }
    }
}

enum AudioEngineError: Equatable {
    case microphonePermissionDenied
    case microphoneUnavailable
    case audioSessionUnavailable
    case engineStartFailed

    var message: String {
        switch self {
        case .microphonePermissionDenied:
            String(localized: "需要麦克风访问权限。")
        case .microphoneUnavailable:
            String(localized: "麦克风不可用。")
        case .audioSessionUnavailable:
            String(localized: "音频暂时不可用，请稍后重试。")
        case .engineStartFailed:
            String(localized: "无法启动音频引擎，请重试。")
        }
    }
}

protocol AudioSessionCoordinating {
    func activateForRecording() throws
    func activateForPlayback() throws
    func deactivate()
}

final class AudioSessionCoordinator: AudioSessionCoordinating {
    static let shared = AudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()

    private init() { }

    var currentSampleRate: Double { session.sampleRate }
    var currentIOBufferDuration: TimeInterval { session.ioBufferDuration }

    func activateForRecording() throws {
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    func activateForPlayback() throws {
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
