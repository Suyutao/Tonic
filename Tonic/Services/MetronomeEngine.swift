import AVFoundation
import Combine
import Foundation

final class MetronomeEngine: ObservableObject {
    @Published private(set) var state: AudioEngineState = .idle
    @Published private(set) var currentBeat = 0
    @Published private(set) var activeBeatsPerBar = 4
    @Published private(set) var hasPendingConfiguration = false

    var isPlaying: Bool { state == .running }

    private let engine = AVAudioEngine()
    private let sessionCoordinator: AudioSessionCoordinating
    private var stateMachine = AudioEngineStateMachine()
    private let player = AVAudioPlayerNode()
    private let accentedBuffer: AVAudioPCMBuffer
    private let regularBuffer: AVAudioPCMBuffer
    private var timer: Timer?
    private var activeTempo = 96
    private var pendingConfiguration: (tempo: Int, beatsPerBar: Int)?
    private var notificationTokens: [NSObjectProtocol] = []

    init(sessionCoordinator: AudioSessionCoordinating = AudioSessionCoordinator.shared) {
        self.sessionCoordinator = sessionCoordinator
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        accentedBuffer = Self.makeClickBuffer(format: format, frequency: 1_650)
        regularBuffer = Self.makeClickBuffer(format: format, frequency: 1_100)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        observeAudioSession()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func start(tempo: Int, beatsPerBar: Int) {
        stop()
        transition(.begin)
        do {
            try sessionCoordinator.activateForPlayback()
        } catch {
            transition(.failed(.audioSessionUnavailable))
            return
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            sessionCoordinator.deactivate()
            transition(.failed(.engineStartFailed))
            return
        }

        transition(.started)
        activeTempo = tempo
        activeBeatsPerBar = beatsPerBar
        currentBeat = 0
        playClick(accented: true)
        scheduleNextBeat()
    }

    func update(tempo: Int, beatsPerBar: Int) {
        guard isPlaying else { return }
        pendingConfiguration = (tempo, beatsPerBar)
        hasPendingConfiguration = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        sessionCoordinator.deactivate()
        transition(.stopped)
        currentBeat = 0
        pendingConfiguration = nil
        hasPendingConfiguration = false
    }

    private func scheduleNextBeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 60 / Double(activeTempo), repeats: false) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            if currentBeat == activeBeatsPerBar - 1 {
                currentBeat = 0
                if let pendingConfiguration {
                    activeTempo = pendingConfiguration.tempo
                    activeBeatsPerBar = pendingConfiguration.beatsPerBar
                    self.pendingConfiguration = nil
                    hasPendingConfiguration = false
                }
                playClick(accented: true)
            } else {
                currentBeat += 1
                playClick(accented: false)
            }
            scheduleNextBeat()
        }
    }

    private func playClick(accented: Bool) {
        player.scheduleBuffer(accented ? accentedBuffer : regularBuffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markInterrupted()
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: reasonValue) == .oldDeviceUnavailable else { return }
            self?.markInterrupted()
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.markInterrupted()
        })
    }

    private func markInterrupted() {
        guard isPlaying else { return }
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        currentBeat = 0
        pendingConfiguration = nil
        hasPendingConfiguration = false
        sessionCoordinator.deactivate()
        transition(.interrupted)
    }

    private func transition(_ event: AudioEngineEvent) {
        stateMachine.send(event)
        state = stateMachine.state
    }

    private static func makeClickBuffer(format: AVAudioFormat, frequency: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(format.sampleRate * 0.045)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / Double(frameCount)
            samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / format.sampleRate) * pow(1 - progress, 8) * 0.7)
        }
        return buffer
    }
}
