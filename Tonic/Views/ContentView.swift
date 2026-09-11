import SwiftUI
import UIKit
import CoreHaptics

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var detector = PitchDetector()
    @StateObject private var metronome = MetronomeEngine()
    @AppStorage("referencePitch") private var referencePitch = 440.0
    @AppStorage("pitchInputSensitivity") private var pitchInputSensitivity = PitchInputSensitivity.maximum.rawValue
    @AppStorage("noteNamingStyle") private var noteNamingStyle = NoteNamingStyle.letter.rawValue
    @AppStorage("accidentalStyle") private var accidentalStyle = AccidentalStyle.sharp.rawValue
    @AppStorage("usesNumericMorph") private var usesNumericMorph = false
    @AppStorage("metronomeTempo") private var tempo = 96.0
    @AppStorage("metronomeBeatsPerBar") private var beatsPerBar = 4
    @State private var selectedPage = 0
    @State private var tunerHistory: [Double] = []
    @State private var tunerNoteChanges: [TunerNoteChange] = []
    @State private var lastDetectedFrequency: Double?
    @State private var tapTempo = TapTempoAverager()
    @State private var showsSettingsAlert = false
    @State private var showsSettingsSheet = false
    @State private var isPageTransitioning = false
    @AppStorage("appearanceMode") private var appearanceMode = "dark"

    init(initialPage: Int = 0) {
        _selectedPage = State(initialValue: initialPage)
    }

    private var reading: PitchReading? {
        detector.frequency.map { PitchReading(frequency: $0, referencePitch: referencePitch) }
    }

    private var displayedReading: PitchReading? {
        (detector.frequency ?? lastDetectedFrequency).map {
            PitchReading(frequency: $0, referencePitch: referencePitch)
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { _ in
                VStack(spacing: 0) {
                    TabView(selection: $selectedPage) {
                        TunerPage(detector: detector, reading: displayedReading, history: tunerHistory, noteChanges: tunerNoteChanges, noteNamingStyle: noteNamingPreference, accidentalStyle: accidentalPreference, usesNumericMorph: usesNumericMorph).tag(0)
                        MetronomePage(metronome: metronome, tempo: $tempo, beatsPerBar: $beatsPerBar, tap: registerTap).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .simultaneousGesture(pageTransitionGesture)
                    .frame(maxHeight: .infinity)

                Button(action: togglePrimaryAction) {
                        Text(primaryButtonTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                }
                .modifier(TonicPrimaryButtonStyle())
                .foregroundStyle(ToneTunerDesign.primaryLabel)
                .disabled(isPageTransitioning)
                .frame(height: 73)
                .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .background(ToneTunerDesign.background)
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .navigationTitle(selectedPage == 0 ? "调音器" : "节拍器")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettingsSheet = true } label: {
                        Image(systemName: "gear")
                    }
                    .tint(ToneTunerDesign.primaryLabel)
                    .accessibilityLabel("设置")
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .tint(ToneTunerDesign.tint)
        .onAppear {
            detector.setInputSensitivity(pitchInputSensitivityPreference)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--tonic-diagnostic") {
                detector.start()
            }
#endif
        }
        .onChange(of: detector.frequency) { _, frequency in
            guard let frequency else { return }
            lastDetectedFrequency = frequency
        }
        .onChange(of: reading?.cents) { _, cents in
            guard let cents else { return }
            tunerHistory.append(cents)
            let discardedCount = max(0, tunerHistory.count - 120)
            if discardedCount > 0 {
                tunerHistory.removeFirst(discardedCount)
                tunerNoteChanges = tunerNoteChanges.compactMap { $0.shifted(leftBy: discardedCount) }
            }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--tonic-diagnostic"),
               let reading {
                let timestampText = String(format: "%.3f", Date().timeIntervalSince1970)
                let displayFrequency = String(format: "%.4f", reading.frequency)
                let letterName = reading.noteName(style: .letter, accidentals: accidentalPreference)
                let solfegeName = reading.noteName(style: .solfege, accidentals: accidentalPreference)
                let centsText = String(format: "%.4f", reading.cents)
                print("TONIC_DISPLAY,\(timestampText),\(displayFrequency),\(letterName),\(solfegeName),\(centsText),\(tunerHistory.count - 1),\(centsText)")
                fflush(stdout)
            }
#endif
        }
        .onChange(of: reading?.noteName(style: noteNamingPreference, accidentals: accidentalPreference)) { oldName, newName in
            guard let newName, newName != oldName, !tunerHistory.isEmpty else { return }
            tunerNoteChanges.append(TunerNoteChange(index: tunerHistory.count - 1, name: newName))
            if tunerNoteChanges.count > 12 { tunerNoteChanges.removeFirst(tunerNoteChanges.count - 12) }
        }
        .onChange(of: selectedPage) { _, page in
            TonicHaptics.shared.playPageSwitch()
            if page == 0 {
                metronome.stop()
            } else {
                detector.stop()
            }
        }
        .onChange(of: pitchInputSensitivity) { _, _ in
            detector.setInputSensitivity(pitchInputSensitivityPreference)
        }
        .onChange(of: tempo) { _, _ in metronome.update(tempo: Int(tempo.rounded()), beatsPerBar: beatsPerBar) }
        .onChange(of: beatsPerBar) { _, value in metronome.update(tempo: Int(tempo.rounded()), beatsPerBar: value) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { detector.stop(); metronome.stop() }
            else { detector.refreshAuthorization() }
        }
        .alert("需要麦克风访问权限", isPresented: $showsSettingsAlert) {
            Button("打开设置") { openSettings() }
            Button("取消", role: .cancel) { }
        } message: { Text("请在系统“设置”中允许 Tonic 使用麦克风。") }
        .sheet(isPresented: $showsSettingsSheet) {
            TonicSettingsView(referencePitch: $referencePitch, appearanceMode: $appearanceMode, noteNamingStyle: $noteNamingStyle, accidentalStyle: $accidentalStyle, pitchInputSensitivity: $pitchInputSensitivity, usesNumericMorph: $usesNumericMorph)
                .preferredColorScheme(preferredColorScheme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        selectedPage == 0 ? (detector.isRunning ? "停止" : "开始") : (metronome.isPlaying ? "停止" : "开始")
    }

    private var noteNamingPreference: NoteNamingStyle {
        NoteNamingStyle(rawValue: noteNamingStyle) ?? .letter
    }

    private var accidentalPreference: AccidentalStyle {
        AccidentalStyle(rawValue: accidentalStyle) ?? .sharp
    }

    private var pitchInputSensitivityPreference: PitchInputSensitivity {
        PitchInputSensitivity(rawValue: pitchInputSensitivity) ?? .maximum
    }

    private var preferredColorScheme: ColorScheme? {
        appearanceMode == "dark" ? .dark : nil
    }

    private var pageTransitionGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { _ in
                isPageTransitioning = true
            }
            .onEnded { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isPageTransitioning = false
                }
            }
    }

    private func togglePrimaryAction() {
        guard !isPageTransitioning else { return }
        if selectedPage == 0 {
            if detector.isRunning {
                detector.stop()
            } else {
                metronome.stop()
                if detector.authorization == .denied {
                    showsSettingsAlert = true
                } else if detector.authorization == .undetermined {
                    detector.requestAndStart()
                } else {
                    detector.start()
                }
            }
        } else {
            if metronome.isPlaying {
                metronome.stop()
            } else {
                detector.stop()
                metronome.start(tempo: Int(tempo.rounded()), beatsPerBar: beatsPerBar)
            }
        }
    }

    private func registerTap() {
        guard let candidate = tapTempo.registerTap(at: Date.timeIntervalSinceReferenceDate) else { return }
        tempo = Double(candidate)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview { ContentView() }

private final class TonicHaptics {
    static let shared = TonicHaptics()

    private let engine: CHHapticEngine?

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engine = nil
            return
        }

        do {
            let engine = try CHHapticEngine()
            self.engine = engine
            try? engine.start()
        } catch {
            engine = nil
        }
    }

    func playPageSwitch() {
        guard let engine else {
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }

        do {
            try engine.start()
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.36),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.20)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

private struct TonicSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var referencePitch: Double
    @Binding var appearanceMode: String
    @Binding var noteNamingStyle: String
    @Binding var accidentalStyle: String
    @Binding var pitchInputSensitivity: String
    @Binding var usesNumericMorph: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("调音器") {
                    Picker("参考音高", selection: $referencePitch) {
                        Text("A4 = 432 Hz").tag(432.0)
                        Text("A4 = 440 Hz").tag(440.0)
                        Text("A4 = 442 Hz").tag(442.0)
                    }
                    Picker("音名显示", selection: $noteNamingStyle) {
                        Text("字母音名").tag(NoteNamingStyle.letter.rawValue)
                        Text("唱名").tag(NoteNamingStyle.solfege.rawValue)
                    }
                    Picker("变化音", selection: $accidentalStyle) {
                        Text("升号 (♯)").tag(AccidentalStyle.sharp.rawValue)
                        Text("降号 (♭)").tag(AccidentalStyle.flat.rawValue)
                    }
                    Picker("检测灵敏度", selection: $pitchInputSensitivity) {
                        Text("最大").tag(PitchInputSensitivity.maximum.rawValue)
                        Text("高").tag(PitchInputSensitivity.high.rawValue)
                        Text("标准").tag(PitchInputSensitivity.standard.rawValue)
                    }
                    Toggle("Morph 数字动效", isOn: $usesNumericMorph)
                }
                Section("外观") {
                    Picker("外观", selection: $appearanceMode) {
                        Text("深色").tag("dark")
                        Text("跟随系统").tag("system")
                    }
                }
                Section("语言") {
                    Button(action: openAppSettings) {
                        Label("在系统设置中更改语言", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
