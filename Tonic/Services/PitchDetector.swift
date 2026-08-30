import AVFoundation
import Combine
import Foundation

final class PitchDetector: ObservableObject {
    @Published private(set) var frequency: Double?
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var authorization: AVAudioApplication.recordPermission
    @Published private(set) var state: AudioEngineState = .idle

    var isRunning: Bool { state == .running }

    private let engine = AVAudioEngine()
    private let sessionCoordinator: AudioSessionCoordinating
    private var stateMachine = AudioEngineStateMachine()
    private var isTapInstalled = false
    private var smoothedFrequency: Double?
    private var notificationTokens: [NSObjectProtocol] = []

    init(sessionCoordinator: AudioSessionCoordinating = AudioSessionCoordinator.shared) {
        self.sessionCoordinator = sessionCoordinator
        authorization = AVAudioApplication.shared.recordPermission
        observeAudioSession()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func requestAndStart() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            await MainActor.run {
                authorization = granted ? .granted : .denied
                if granted {
                    start()
                } else {
                    transition(.failed(.microphonePermissionDenied))
                }
            }
        }
    }

    func refreshAuthorization() {
        authorization = AVAudioApplication.shared.recordPermission
    }

    func start() {
        refreshAuthorization()
        guard authorization == .granted else {
            if authorization == .denied || authorization == .undetermined {
                transition(.failed(.microphonePermissionDenied))
            } else {
                transition(.failed(.microphoneUnavailable))
            }
            return
        }

        transition(.begin)
        do {
            try sessionCoordinator.activateForRecording()
        } catch {
            transition(.failed(.audioSessionUnavailable))
            return
        }

        do {
            installTapIfNeeded()
            engine.prepare()
            try engine.start()
            transition(.started)
        } catch {
            engine.stop()
            if isTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                isTapInstalled = false
            }
            sessionCoordinator.deactivate()
            transition(.failed(.engineStartFailed))
        }
    }

    func stop() {
        engine.stop()
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        sessionCoordinator.deactivate()
        transition(.stopped)
        frequency = nil
        inputLevel = 0
        smoothedFrequency = nil
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
        guard isRunning else { return }
        engine.stop()
        frequency = nil
        inputLevel = 0
        smoothedFrequency = nil
        sessionCoordinator.deactivate()
        transition(.interrupted)
    }

    private func transition(_ event: AudioEngineEvent) {
        stateMachine.send(event)
        state = stateMachine.state
    }

    private func installTapIfNeeded() {
        guard !isTapInstalled else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_536, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let result = Self.estimatePitch(samples: samples, count: Int(buffer.frameLength), sampleRate: format.sampleRate)
            let smoothed = self?.smoothed(result.frequency)
            DispatchQueue.main.async {
                guard let self else { return }
                self.inputLevel = result.level
                self.frequency = smoothed
            }
        }
        isTapInstalled = true
    }

    private static func estimatePitch(samples: UnsafePointer<Float>, count: Int, sampleRate: Double) -> (frequency: Double?, level: Float) {
        guard count > 2 else { return (nil, 0) }
        var energy: Float = 0
        for index in 0..<count {
            let value = samples[index]
            energy += value * value
        }
        let level = sqrt(energy / Float(count))
        guard level > 0.012 else { return (nil, level) }

        let minLag = max(2, Int(sampleRate / 1_100))
        let maxLag = min(Int(sampleRate / 55), count / 2)
        guard minLag < maxLag else { return (nil, level) }
        func score(at lag: Int) -> Float {
            var correlation: Float = 0
            var firstEnergy: Float = 0
            var secondEnergy: Float = 0
            for index in 0..<(count - lag) {
                let first = samples[index]
                let second = samples[index + lag]
                correlation += first * second
                firstEnergy += first * first
                secondEnergy += second * second
            }
            return correlation / sqrt(max(firstEnergy * secondEnergy, .leastNonzeroMagnitude))
        }

        var coarseBestLag = minLag
        var coarseBestScore: Float = -.infinity
        for lag in stride(from: minLag, through: maxLag, by: 4) {
            let candidate = score(at: lag)
            if candidate > coarseBestScore {
                coarseBestScore = candidate
                coarseBestLag = lag
            }
        }

        let lowerBound = max(minLag, coarseBestLag - 4)
        let upperBound = min(maxLag, coarseBestLag + 4)
        var bestLag = lowerBound
        var bestScore: Float = -.infinity
        var localScores: [Int: Float] = [:]
        for lag in lowerBound...upperBound {
            let candidate = score(at: lag)
            localScores[lag] = candidate
            if candidate > bestScore {
                bestScore = candidate
                bestLag = lag
            }
        }
        guard bestScore > 0.62 else { return (nil, level) }
        var fractionalLag = Double(bestLag)
        if let leftScore = localScores[bestLag - 1], let centerScore = localScores[bestLag], let rightScore = localScores[bestLag + 1] {
            let left = Double(leftScore)
            let center = Double(centerScore)
            let right = Double(rightScore)
            let denominator = left - 2 * center + right
            if abs(denominator) > .leastNonzeroMagnitude {
                fractionalLag += 0.5 * (left - right) / denominator
            }
        }
        return (sampleRate / fractionalLag, level)
    }

    private func smoothed(_ estimate: Double?) -> Double? {
        guard let estimate else {
            smoothedFrequency = nil
            return nil
        }
        let result = smoothedFrequency.map { $0 + (estimate - $0) * 0.7 } ?? estimate
        smoothedFrequency = result
        return result
    }
}
