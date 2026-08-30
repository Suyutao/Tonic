import SwiftUI
import UIKit

struct TunerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var detector = PitchDetector()
    @AppStorage("referencePitch") private var referencePitch = 440.0
    @AppStorage("noteNamingStyle") private var noteNamingStyle = NoteNamingStyle.letter.rawValue
    @AppStorage("accidentalStyle") private var accidentalStyle = AccidentalStyle.sharp.rawValue
    @State private var showsSettingsAlert = false
    @State private var history: [Double] = []

    private var reading: PitchReading? { detector.frequency.map { PitchReading(frequency: $0, referencePitch: referencePitch) } }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let buttonHeight = CGFloat(73)
                let verticalGap = CGFloat(20)
                let topInset = CGFloat(10)
                let bottomInset = CGFloat(20)
                let layoutHeight = proxy.size.height
                let panelHeight = max(0, layoutHeight - topInset - verticalGap - buttonHeight - bottomInset)

                VStack(spacing: verticalGap) {
                    tunerPanel
                        .frame(height: panelHeight)
                    statusView
                        .fixedSize(horizontal: false, vertical: true)
                    tuningButton
                        .padding(.horizontal, 10)
                }
                .padding(.horizontal, 10)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(height: layoutHeight, alignment: .top)
            }
            .background(ToneTunerDesign.background)
            .safeAreaInset(edge: .top, spacing: 0) { InlineLargeToolbar(title: "调音器") { referencePitchMenu } }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: reading?.cents) { _, cents in
                guard let cents else { return }
                history.append(cents)
                if history.count > 120 { history.removeFirst(history.count - 120) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { detector.stop() } else { detector.refreshAuthorization() }
            }
            .onDisappear { detector.stop() }
            .alert("需要麦克风访问权限", isPresented: $showsSettingsAlert) {
                Button("打开设置") { openSettings() }
                Button("取消", role: .cancel) { }
            } message: { Text("请在系统“设置”中允许 Tonic 使用麦克风。") }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tunerPanel: some View {
        VStack(spacing: 0) {
            RainbowPositionStrip(cents: reading?.cents)
                .padding(.horizontal, 11)
            Color.clear.frame(height: 93)
            VStack(spacing: 10) {
                Text(reading.map { String(format: "%.0f Hz", $0.frequency) } ?? "-- Hz")
                    .font(.system(size: 22))
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
                Text(reading?.noteName(style: noteNamingPreference, accidentals: accidentalPreference) ?? "--")
                    .font(.system(size: 128, weight: .bold, design: .rounded))
                    .foregroundStyle(ToneTunerDesign.primaryLabel)
                    .shadow(color: ToneTunerDesign.primaryLabel.opacity(0.28), radius: 6, y: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .minimumScaleFactor(0.5)
                Rectangle().fill(Color(red: 138 / 255, green: 138 / 255, blue: 138 / 255)).frame(width: 229, height: 1)
                Text(reading.map { String(format: "%+.0f¢", $0.cents) } ?? "0¢")
                    .font(.system(size: 22)).foregroundStyle(ToneTunerDesign.secondaryLabel)
                    .offset(y: -6)
            }
            .padding(10).frame(maxWidth: .infinity).frame(height: 218)
            Spacer(minLength: 24)
            TunerHistoryGraph(values: history)
                .frame(height: 162).padding(12).toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 24)
                .padding(.horizontal, 11).padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 36)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private var noteNamingPreference: NoteNamingStyle {
        NoteNamingStyle(rawValue: noteNamingStyle) ?? .letter
    }

    private var accidentalPreference: AccidentalStyle {
        AccidentalStyle(rawValue: accidentalStyle) ?? .sharp
    }

    @ViewBuilder private var statusView: some View {
        if case .failed(let error) = detector.state { recoveryRow(error.message) }
        else if detector.state == .interrupted { recoveryRow("音频已中断，请重新开始调音。") }
    }

    private func recoveryRow(_ text: String) -> some View {
        VStack(spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(ToneTunerDesign.secondaryLabel).multilineTextAlignment(.center)
            Button(detector.authorization == .denied ? "打开设置" : "重试") { detector.authorization == .denied ? openSettings() : detector.start() }
        }
    }

    private var referencePitchMenu: some View {
        Menu {
            Picker("A4", selection: $referencePitch) {
                Text("A4 = 432 Hz").tag(432.0); Text("A4 = 440 Hz").tag(440.0); Text("A4 = 442 Hz").tag(442.0)
            }
        } label: {
            Image(systemName: "gear")
                .frame(width: 44, height: 44)
        }
        .modifier(TonicToolbarButtonStyle())
        .tint(ToneTunerDesign.primaryLabel)
        .accessibilityLabel("参考音高")
    }

    private var tuningButton: some View {
        Button(action: toggleTuning) {
            Text(detector.isRunning ? "停止" : "开始").font(.system(size: 28, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 73)
        }
        .buttonStyle(.plain).foregroundStyle(ToneTunerDesign.primaryLabel)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 37)
        .accessibilityHint(detector.authorization == .denied ? "需要在设置中允许麦克风访问" : "使用麦克风识别音高")
    }

    private func toggleTuning() {
        if detector.isRunning { detector.stop() }
        else if detector.authorization == .denied { showsSettingsAlert = true }
        else if detector.authorization == .undetermined { detector.requestAndStart() }
        else { detector.start() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct RainbowPositionStrip: View {
    let cents: Double?
    private var position: CGFloat { CGFloat((min(max(cents ?? 0, -50), 50) + 50) / 100) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: [
                    .init(color: Color(red: 1, green: 34 / 255, blue: 0), location: 0),
                    .init(color: Color(red: 1, green: 205 / 255, blue: 6 / 255), location: 0.24621768),
                    .init(color: Color(red: 82 / 255, green: 1, blue: 2 / 255), location: 0.50068617),
                    .init(color: Color(red: 17 / 255, green: 1, blue: 247 / 255), location: 0.74802005),
                    .init(color: Color(red: 179 / 255, green: 0, blue: 1), location: 1)
                ], startPoint: .leading, endPoint: .trailing)
                    .frame(width: proxy.size.width, height: 10, alignment: .topLeading)
                RoundedTriangle(cornerRadius: 2)
                    .fill(ToneTunerDesign.primaryLabel)
                    .frame(width: 20, height: 20)
                    .offset(x: max(0, min(proxy.size.width - 20, proxy.size.width * position - 10)), y: 13)
            }
        }.frame(height: 33).accessibilityHidden(true)
    }
}

struct RoundedTriangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 4)
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let trailing = CGPoint(x: rect.maxX, y: rect.maxY)
        let leading = CGPoint(x: rect.minX, y: rect.maxY)
        let topInset = radius * 0.9
        let sideInset = radius * 0.45

        var path = Path()
        path.move(to: CGPoint(x: top.x + topInset, y: top.y + topInset))
        path.addLine(to: CGPoint(x: trailing.x - sideInset, y: trailing.y - radius))
        path.addQuadCurve(to: CGPoint(x: trailing.x - radius, y: trailing.y), control: trailing)
        path.addLine(to: CGPoint(x: leading.x + radius, y: leading.y))
        path.addQuadCurve(to: CGPoint(x: leading.x + sideInset, y: leading.y - radius), control: leading)
        path.addLine(to: CGPoint(x: top.x - topInset, y: top.y + topInset))
        path.addQuadCurve(to: CGPoint(x: top.x + topInset, y: top.y + topInset), control: top)
        path.closeSubpath()
        return path
    }
}

enum NoteNamingStyle: String {
    case letter
    case solfege
}

enum AccidentalStyle: String {
    case sharp
    case flat
}

struct PitchReading {
    let frequency: Double
    let midi: Int
    let cents: Double

    init(frequency: Double, referencePitch: Double) {
        let exactMidi = 69 + 12 * log2(frequency / referencePitch)
        midi = Int(exactMidi.rounded()); cents = (exactMidi - Double(midi)) * 100; self.frequency = frequency
    }

    var noteName: String {
        noteName(style: .letter, accidentals: .sharp)
    }

    func noteName(style: NoteNamingStyle, accidentals: AccidentalStyle) -> String {
        let names: [String]
        switch (style, accidentals) {
        case (.letter, .sharp):
            names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        case (.letter, .flat):
            names = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        case (.solfege, .sharp):
            names = ["Do", "Do♯", "Re", "Re♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
        case (.solfege, .flat):
            names = ["Do", "Re♭", "Re", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]
        }
        return "\(names[(midi % 12 + 12) % 12])\(Int(floor(Double(midi) / 12)) - 1)"
    }
    var isInTune: Bool { abs(cents) <= 5 }
}

struct TunerPage: View {
    @ObservedObject var detector: PitchDetector
    let reading: PitchReading?
    let history: [Double]
    let noteChanges: [TunerNoteChange]
    let noteNamingStyle: NoteNamingStyle
    let accidentalStyle: AccidentalStyle

    var body: some View {
        tunerPanel
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ToneTunerDesign.background)
    }

    private var tunerPanel: some View {
        VStack(spacing: 0) {
            RainbowPositionStrip(cents: reading?.cents)
                .padding(.horizontal, 11)
            Color.clear.frame(height: 93)
            VStack(spacing: 10) {
                Text(reading.map { String(format: "%.0f Hz", $0.frequency) } ?? "-- Hz")
                    .font(.title2)
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
                Text(reading?.noteName(style: noteNamingStyle, accidentals: accidentalStyle) ?? "--")
                    .font(.system(size: 128, weight: .bold, design: .rounded))
                    .foregroundStyle(ToneTunerDesign.primaryLabel)
                    .shadow(color: ToneTunerDesign.primaryLabel.opacity(0.28), radius: 6, y: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .minimumScaleFactor(0.5)
                Rectangle()
                    .fill(Color(red: 138 / 255, green: 138 / 255, blue: 138 / 255))
                    .frame(width: 229, height: 1)
                Text(reading.map { String(format: "%+.0f¢", $0.cents) } ?? "0¢")
                    .font(.title2)
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
                    .offset(y: -6)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: 218)
            Spacer(minLength: 24)
            TunerHistoryGraph(values: history, noteChanges: noteChanges)
                .frame(height: 162)
                .padding(12)
                .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 24)
                .padding(.horizontal, 11)
                .padding(.bottom, 11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 36)
        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
    }
}
