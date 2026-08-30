import SwiftUI

struct MetronomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var metronome = MetronomeEngine()
    @AppStorage("metronomeTempo") private var tempo = 96
    @AppStorage("metronomeBeatsPerBar") private var beatsPerBar = 4
    private let reduceMotionOverride: Bool?

    init(reduceMotionOverride: Bool? = nil) {
        self.reduceMotionOverride = reduceMotionOverride
    }

    private var shouldReduceMotion: Bool { reduceMotionOverride ?? reduceMotion }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    metronomeDisplay
                    tempoControl
                    timeSignatureControl
                    statusView
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                playButton.padding(.horizontal).padding(.vertical, 8)
            }
            .navigationTitle("节拍器")
        }
        .onChange(of: tempo) { _, value in metronome.update(tempo: value, beatsPerBar: beatsPerBar) }
        .onChange(of: beatsPerBar) { _, value in metronome.update(tempo: tempo, beatsPerBar: value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { metronome.stop() } }
        .onDisappear { metronome.stop() }
    }

    private var metronomeDisplay: some View {
        VStack(spacing: 14) {
            Text("BPM").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(tempo)").font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
            HStack(spacing: 10) {
                ForEach(0..<metronome.activeBeatsPerBar, id: \.self) { beat in
                    Circle()
                        .fill(beat == metronome.currentBeat && metronome.isPlaying ? (beat == 0 ? Color.indigo : Color.primary) : Color.secondary.opacity(0.2))
                        .frame(width: 18, height: 18)
                        .scaleEffect(!shouldReduceMotion && beat == metronome.currentBeat && metronome.isPlaying ? 1.15 : 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 42)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .toneTunerSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("节拍器")
        .accessibilityValue(metronomeAccessibilityValue)
    }

    private var tempoControl: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { Double(tempo) }, set: { tempo = Int($0.rounded()) }), in: 40...240, step: 1) { Text("速度") } minimumValueLabel: { Text("40") } maximumValueLabel: { Text("240") }
        }
        .padding(18)
        .toneTunerSurface(cornerRadius: 18)
    }

    private var timeSignatureControl: some View {
        HStack {
            Label("拍号", systemImage: "music.note.list")
            Spacer()
            Picker("拍号", selection: $beatsPerBar) {
                Text("2/4").tag(2); Text("3/4").tag(3); Text("4/4").tag(4); Text("6/8").tag(6)
            }.pickerStyle(.menu)
        }
        .padding(18)
        .toneTunerSurface(cornerRadius: 18)
    }

    @ViewBuilder private var statusView: some View {
        if metronome.hasPendingConfiguration {
            Label("新速度和拍号将在下一小节生效", systemImage: "clock.arrow.circlepath")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if metronome.state == .interrupted {
            recoveryRow("音频已中断，请重新开始。")
        } else if case .failed(let error) = metronome.state {
            recoveryRow(error.message)
        }
    }

    private func recoveryRow(_ text: String) -> some View {
        VStack(spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") { metronome.start(tempo: tempo, beatsPerBar: beatsPerBar) }
        }
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            Label(metronome.isPlaying ? "停止" : "开始", systemImage: metronome.isPlaying ? "stop.fill" : "play.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("以当前速度播放节拍")
    }

    private var metronomeAccessibilityValue: String {
        if metronome.isPlaying {
            return String(
                format: String(localized: "每分钟 %1$ld 拍，第 %2$ld 拍，共 %3$ld 拍"),
                locale: .current,
                tempo,
                metronome.currentBeat + 1,
                metronome.activeBeatsPerBar
            )
        }
        return String(format: String(localized: "已停止，每分钟 %ld 拍"), locale: .current, tempo)
    }

    private func togglePlayback() {
        metronome.isPlaying ? metronome.stop() : metronome.start(tempo: tempo, beatsPerBar: beatsPerBar)
    }
}
