import AVFoundation
import Combine
import Foundation
import Darwin

enum PitchInputSensitivity: String {
    case maximum
    case high
    case standard

    var minimumInputLevel: Float {
        switch self {
        case .maximum: .leastNonzeroMagnitude
        case .high: 0.002
        case .standard: 0.004
        }
    }
}

final class PitchDetector: ObservableObject {
    @Published private(set) var frequency: Double?
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var authorization: AVAudioApplication.recordPermission
    @Published private(set) var state: AudioEngineState = .idle

    var isRunning: Bool { state == .running }

    private let engine = AVAudioEngine()
    private let sessionCoordinator: AudioSessionCoordinating
    private let lifecycleQueue = DispatchQueue(label: "com.suyutao.tonic.pitch-lifecycle", qos: .userInitiated)
    private var stateMachine = AudioEngineStateMachine()
    private var isTapInstalled = false
    private var smoothedFrequency: Double?
    private var notificationTokens: [NSObjectProtocol] = []
    private var lastPublishedAt = 0.0
    private var missedFrames = 0
    private var rejectedFrames = 0
    private var pendingFrequency: Double?
    private var pendingFrequencyFrames = 0
#if DEBUG
    private var lastDiagnosticAt = 0.0
#endif
    private var minimumInputLevel = PitchInputSensitivity.maximum.minimumInputLevel

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

    func setInputSensitivity(_ sensitivity: PitchInputSensitivity) {
        minimumInputLevel = sensitivity.minimumInputLevel
    }

    func start() {
        guard !state.isActive else { return }
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
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.sessionCoordinator.activateForRecording()
                self.installTapIfNeeded()
                self.engine.prepare()
                try self.engine.start()
                DispatchQueue.main.async { [weak self] in
                    self?.transition(.started)
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--tonic-diagnostic") {
                        print("TONIC_READY")
                        fflush(stdout)
                    }
#endif
                }
            } catch is AudioEngineError {
                self.stopEngineOnLifecycleQueue()
                DispatchQueue.main.async { [weak self] in
                    self?.transition(.failed(.audioSessionUnavailable))
                }
            } catch {
                self.stopEngineOnLifecycleQueue()
                DispatchQueue.main.async { [weak self] in
                    self?.transition(.failed(.engineStartFailed))
                }
            }
        }
    }

    func stop() {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.stopEngineOnLifecycleQueue()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.transition(.stopped)
                self.frequency = nil
                self.inputLevel = 0
                self.smoothedFrequency = nil
                self.missedFrames = 0
                self.rejectedFrames = 0
                self.pendingFrequency = nil
                self.pendingFrequencyFrames = 0
                self.lastPublishedAt = 0
            }
        }
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
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.stopEngineOnLifecycleQueue()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.frequency = nil
                self.inputLevel = 0
                self.smoothedFrequency = nil
                self.transition(.interrupted)
            }
        }
    }

    private func transition(_ event: AudioEngineEvent) {
        stateMachine.send(event)
        state = stateMachine.state
    }

    private func installTapIfNeeded() {
        guard !isTapInstalled else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // 1536 frames cover a full period at 55 Hz while keeping analysis latency near 35 ms at 44.1 kHz.
        input.installTap(onBus: 0, bufferSize: 1_536, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let result = Self.estimatePitch(samples: samples, count: Int(buffer.frameLength), sampleRate: format.sampleRate, minimumInputLevel: self?.minimumInputLevel ?? .leastNonzeroMagnitude)
            let smoothed = self?.smoothed(result.frequency)
            let now = ProcessInfo.processInfo.systemUptime
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--tonic-diagnostic"),
               now - (self?.lastDiagnosticAt ?? 0) >= 0.1 {
                self?.lastDiagnosticAt = now
                let timestamp = Date().timeIntervalSince1970
                let rawText = result.frequency.map { String(format: "%.4f", $0) } ?? ""
                let smoothText = smoothed.map { String(format: "%.4f", $0) } ?? ""
                print(String(format: "TONIC_CSV,%.3f,%@,%@,%.6f", timestamp, rawText, smoothText, result.level))
            }
#endif
            guard now - (self?.lastPublishedAt ?? 0) >= (1.0 / 60.0) else { return }
            self?.lastPublishedAt = now
            DispatchQueue.main.async {
                guard let self else { return }
                self.inputLevel = result.level
                self.frequency = smoothed
            }
        }
        isTapInstalled = true
    }

    private func stopEngineOnLifecycleQueue() {
        engine.stop()
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        sessionCoordinator.deactivate()
    }

    static func estimatePitch(samples: UnsafePointer<Float>, count: Int, sampleRate: Double, minimumInputLevel: Float = PitchInputSensitivity.maximum.minimumInputLevel) -> (frequency: Double?, level: Float) {
        guard count > 2 else { return (nil, 0) }
        var mean: Float = 0
        for index in 0..<count { mean += samples[index] }
        mean /= Float(count)

        var energy: Float = 0
        for index in 0..<count {
            let centered = samples[index] - mean
            energy += centered * centered
        }
        let level = sqrt(energy / Float(count))
        guard level > minimumInputLevel else { return (nil, level) }

        // Analyze every other sample. The time window stays ~35 ms, while the
        // quadratic difference pass does roughly one quarter of the work.
        let analysisSamples = stride(from: 0, to: count, by: 2).map { samples[$0] }
        let analysisCount = analysisSamples.count
        let analysisRate = sampleRate / 2
        guard analysisCount > 2 else { return (nil, level) }

        var analysisMean: Float = 0
        for sample in analysisSamples { analysisMean += sample }
        analysisMean /= Float(analysisCount)

        let minLag = max(2, Int(analysisRate / 1_100))
        // A lag may use the available prefix of the window; limiting to count / 2
        // would exclude the lowest supported fundamental from a 1536-frame tap.
        let maxLag = min(Int(analysisRate / 55), analysisCount - 2)
        guard minLag < maxLag else { return (nil, level) }

        var difference = [Float](repeating: 0, count: maxLag + 1)
        for lag in 1...maxLag {
            var sum: Float = 0
            for index in 0..<(analysisCount - lag) {
                let delta = (analysisSamples[index] - analysisMean) - (analysisSamples[index + lag] - analysisMean)
                sum += delta * delta
            }
            difference[lag] = sum
        }

        var cumulativeDifference = [Float](repeating: 1, count: maxLag + 1)
        var runningSum: Float = 0
        for lag in 1...maxLag {
            runningSum += difference[lag]
            cumulativeDifference[lag] = difference[lag] * Float(lag) / max(runningSum, .leastNonzeroMagnitude)
        }

        // The input microphone is exposed to reflections and room noise. A loose
        // threshold can select an earlier, non-fundamental period; only accept a
        // pronounced YIN minimum for a live reading.
        let threshold: Float = 0.12
        var bestLag: Int?
        for lag in minLag..<maxLag where cumulativeDifference[lag] < threshold {
            var localMinimum = lag
            while localMinimum + 1 < maxLag,
                  cumulativeDifference[localMinimum + 1] < cumulativeDifference[localMinimum] {
                localMinimum += 1
            }
            bestLag = localMinimum
            break
        }
        if bestLag == nil {
            bestLag = (minLag...maxLag).min { cumulativeDifference[$0] < cumulativeDifference[$1] }
        }

        guard let lag = bestLag, cumulativeDifference[lag] < 0.20 else { return (nil, level) }
        var fractionalLag = Double(lag)
        if lag > minLag, lag < maxLag {
            let left = Double(cumulativeDifference[lag - 1])
            let center = Double(cumulativeDifference[lag])
            let right = Double(cumulativeDifference[lag + 1])
            let denominator = left - 2 * center + right
            if abs(denominator) > .leastNonzeroMagnitude {
                fractionalLag += 0.5 * (left - right) / denominator
            }
        }
        guard fractionalLag > 0 else { return (nil, level) }
        return (analysisRate / fractionalLag, level)
    }

    private func smoothed(_ estimate: Double?) -> Double? {
        guard let estimate else {
            missedFrames += 1
            pendingFrequency = nil
            pendingFrequencyFrames = 0
            if missedFrames <= 2 { return smoothedFrequency }
            smoothedFrequency = nil
            rejectedFrames = 0
            return nil
        }
        missedFrames = 0
        if smoothedFrequency == nil {
            if let pending = pendingFrequency {
                let change = abs(estimate - pending) / max(pending, .leastNonzeroMagnitude)
                if change <= 0.05 {
                    pendingFrequencyFrames += 1
                } else {
                    pendingFrequency = estimate
                    pendingFrequencyFrames = 1
                }
            } else {
                pendingFrequency = estimate
                pendingFrequencyFrames = 1
            }
            guard pendingFrequencyFrames >= 2 else { return nil }
            pendingFrequency = nil
            pendingFrequencyFrames = 0
            smoothedFrequency = estimate
            return estimate
        }
        if let previous = smoothedFrequency {
            let ratio = estimate / previous
            let relativeChange = abs(estimate - previous) / max(previous, .leastNonzeroMagnitude)
            if relativeChange > 0.08, (0.75...1.33).contains(ratio) {
                // A genuine note change can still be within the octave guard.
                // Confirm it twice, then avoid dragging the new note toward the old one.
                rejectedFrames += 1
                if rejectedFrames < 2 { return previous }
                rejectedFrames = 0
                smoothedFrequency = estimate
                return estimate
            }
            if !(0.75...1.33).contains(ratio) {
                // Suppress one isolated octave/noise jump, but accept a real note change promptly.
                rejectedFrames += 1
                if rejectedFrames < 2 { return previous }
                rejectedFrames = 0
                smoothedFrequency = estimate
                return estimate
            }
            rejectedFrames = 0
            let result = previous + (estimate - previous) * 0.7
            smoothedFrequency = result
            return result
        }
        let result = estimate
        smoothedFrequency = result
        return result
    }
}
