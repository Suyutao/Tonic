import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var detector = PitchDetector()
    @StateObject private var metronome = MetronomeEngine()
    @AppStorage("referencePitch") private var referencePitch = 440.0
    @AppStorage("pitchInputSensitivity") private var pitchInputSensitivity = PitchInputSensitivity.maximum.rawValue
    @AppStorage("noteNamingStyle") private var noteNamingStyle = NoteNamingStyle.letter.rawValue
    @AppStorage("accidentalStyle") private var accidentalStyle = AccidentalStyle.sharp.rawValue
    @AppStorage("metronomeTempo") private var tempo = 96.0
    @AppStorage("metronomeBeatsPerBar") private var beatsPerBar = 4
    @State private var selectedPage = 0
    @State private var tunerHistory: [Double] = []
    @State private var tunerNoteChanges: [TunerNoteChange] = []
    @State private var tapTempo = TapTempoAverager()
    @State private var showsSettingsAlert = false
    @State private var showsSettingsSheet = false
    @AppStorage("appearanceMode") private var appearanceMode = "dark"

    private var reading: PitchReading? {
        detector.frequency.map { PitchReading(frequency: $0, referencePitch: referencePitch) }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    TabView(selection: $selectedPage) {
                        TunerPage(detector: detector, reading: reading, history: tunerHistory, noteChanges: tunerNoteChanges, noteNamingStyle: noteNamingPreference, accidentalStyle: accidentalPreference).tag(0)
                        MetronomePage(metronome: metronome, tempo: $tempo, beatsPerBar: $beatsPerBar, tap: registerTap).tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxHeight: .infinity)

                Button(action: togglePrimaryAction) {
                        Text(primaryButtonTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                }
                .modifier(TonicPrimaryButtonStyle())
                .foregroundStyle(ToneTunerDesign.primaryLabel)
                .frame(height: 73)
                .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, max(20, proxy.safeAreaInsets.bottom))
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
        .preferredColorScheme(appearanceMode == "dark" ? .dark : nil)
        .tint(ToneTunerDesign.tint)
        .onAppear { detector.setInputSensitivity(pitchInputSensitivityPreference) }
        .onChange(of: reading?.cents) { _, cents in
            guard let cents else { return }
            tunerHistory.append(cents)
            if tunerHistory.count > 120 { tunerHistory.removeFirst(tunerHistory.count - 120) }
        }
        .onChange(of: reading?.noteName(style: noteNamingPreference, accidentals: accidentalPreference)) { oldName, newName in
            guard let newName, newName != oldName, !tunerHistory.isEmpty else { return }
            tunerNoteChanges.append(TunerNoteChange(index: tunerHistory.count - 1, name: newName))
            if tunerNoteChanges.count > 12 { tunerNoteChanges.removeFirst(tunerNoteChanges.count - 12) }
        }
        .onChange(of: selectedPage) { _, page in
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
            TonicSettingsView(referencePitch: $referencePitch, appearanceMode: $appearanceMode, noteNamingStyle: $noteNamingStyle, accidentalStyle: $accidentalStyle, pitchInputSensitivity: $pitchInputSensitivity)
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

    private func togglePrimaryAction() {
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

private struct TonicSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var referencePitch: Double
    @Binding var appearanceMode: String
    @Binding var noteNamingStyle: String
    @Binding var accidentalStyle: String
    @Binding var pitchInputSensitivity: String

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
