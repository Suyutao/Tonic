import SwiftUI
import UIKit

struct TunerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var detector = PitchDetector()
    @AppStorage("referencePitch") private var referencePitch = 440.0
    @State private var showsSettingsAlert = false

    private var reading: PitchReading? { detector.frequency.map { PitchReading(frequency: $0, referencePitch: referencePitch) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text(reading?.noteName ?? "--").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(reading.map { String(format: "%.1f Hz", $0.frequency) } ?? statusText).font(.title3).foregroundStyle(.secondary)
                        Text(reading.map { String(format: "%+.0f cents", $0.cents) } ?? "请弹奏一个音").font(.headline.monospacedDigit()).foregroundStyle(reading?.isInTune == true ? .green : .secondary)
                    }
                    .accessibilityElement(children: .combine)
                    PrecisionTunerGauge(cents: reading?.cents).padding(12).toneTunerSurface()
                    if case .failed(let error) = detector.state { recoveryRow(error.message) }
                    if detector.state == .interrupted { recoveryRow("音频已中断，请重新开始调音。") }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) { tuningButton.padding(.horizontal).padding(.vertical, 8) }
            .navigationTitle("调音器")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { referencePitchMenu } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { detector.stop() } else { detector.refreshAuthorization() } }
            .onDisappear { detector.stop() }
            .alert("需要麦克风访问权限", isPresented: $showsSettingsAlert) {
                Button("打开设置") { openSettings() }
                Button("取消", role: .cancel) { }
            } message: { Text("请在系统“设置”中允许 Tone Tuner 使用麦克风。") }
        }
    }

    private func recoveryRow(_ text: String) -> some View {
        VStack(spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if detector.authorization == .denied {
                Button("打开设置") { openSettings() }
            } else {
                Button("重试") { detector.start() }
            }
        }
    }
    private var statusText: String {
        detector.state == .interrupted ? String(localized: "音频已中断") : String(localized: "等待声音")
    }
    private var referencePitchMenu: some View {
        Menu { Picker("A4", selection: $referencePitch) { Text("A4 = 432 Hz").tag(432.0); Text("A4 = 440 Hz").tag(440.0); Text("A4 = 442 Hz").tag(442.0) } } label: { Text("A4 = \(Int(referencePitch)) Hz").monospacedDigit() }
    }
    private var tuningButton: some View {
        Button(action: toggleTuning) { Label(detector.isRunning ? "停止调音" : "开始调音", systemImage: detector.isRunning ? "stop.fill" : "mic.fill").frame(maxWidth: .infinity, minHeight: 44) }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .accessibilityHint(detector.authorization == .denied ? "需要在设置中允许麦克风访问" : "使用麦克风识别音高")
    }
    private func toggleTuning() {
        if detector.isRunning {
            detector.stop()
        } else if detector.authorization == .denied {
            showsSettingsAlert = true
        } else if detector.authorization == .undetermined {
            detector.requestAndStart()
        } else {
            detector.start()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PitchReading {
    let frequency: Double
    let midi: Int
    let cents: Double

    init(frequency: Double, referencePitch: Double) {
        let exactMidi = 69 + 12 * log2(frequency / referencePitch)
        midi = Int(exactMidi.rounded())
        cents = (exactMidi - Double(midi)) * 100
        self.frequency = frequency
    }

    var noteName: String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(floor(Double(midi) / 12)) - 1
        return "\(names[(midi % 12 + 12) % 12])\(octave)"
    }

    var isInTune: Bool { abs(cents) <= 5 }
}
