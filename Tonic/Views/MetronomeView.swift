import SwiftUI

struct MetronomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var metronome = MetronomeEngine()
    @AppStorage("metronomeTempo") private var tempo = 96.0
    @AppStorage("metronomeBeatsPerBar") private var beatsPerBar = 4
    @State private var tapTempo = TapTempoAverager()
    @State private var hasRegisteredTapTouch = false
    private let reduceMotionOverride: Bool?

    init(reduceMotionOverride: Bool? = nil) { self.reduceMotionOverride = reduceMotionOverride }
    private var shouldReduceMotion: Bool { reduceMotionOverride ?? reduceMotion }
    private var usesCompactControls: Bool { dynamicTypeSize.isAccessibilitySize }
    private var engineTempo: Int { Int(tempo.rounded()) }
    private var tempoMarking: LocalizedStringKey {
        switch engineTempo {
        case ..<80: "广板"
        case ..<120: "行板"
        case ..<160: "中板"
        case ..<200: "快板"
        default: "急板"
        }
    }

    var body: some View {
        GeometryReader { rootProxy in
            let contentHeight = max(0, rootProxy.size.height - rootProxy.safeAreaInsets.top - 54)

            NavigationStack {
                GeometryReader { _ in
                    let bottomButtonHeight = CGFloat(73)
                    let verticalGap = CGFloat(20)
                    let topInset = CGFloat(10)
                    let bottomInset = CGFloat(20)
                    let panelHeight = max(0, contentHeight - topInset - verticalGap - bottomButtonHeight - bottomInset)

                    VStack(spacing: verticalGap) {
                        displayPanel
                            .frame(height: panelHeight)
                        statusView
                            .fixedSize(horizontal: false, vertical: true)
                        playButton
                            .padding(.horizontal, 10)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(height: contentHeight, alignment: .top)
                }
                .background(ToneTunerDesign.background)
                .safeAreaInset(edge: .top, spacing: 0) {
                    InlineLargeToolbar(title: "节拍器") {
                        Button { } label: {
                            Image(systemName: "gear")
                                .frame(width: 44, height: 44)
                        }
                        .modifier(TonicToolbarButtonStyle())
                        .tint(ToneTunerDesign.primaryLabel)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .onChange(of: tempo) { _, _ in metronome.update(tempo: engineTempo, beatsPerBar: beatsPerBar) }
        .onChange(of: beatsPerBar) { _, value in metronome.update(tempo: engineTempo, beatsPerBar: value) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { metronome.stop() } }
        .onDisappear { metronome.stop() }
    }

    private var displayPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(0..<metronome.activeBeatsPerBar, id: \.self) { beat in
                    Circle()
                        .fill(beat == metronome.currentBeat && metronome.isPlaying ? (beat == 0 ? ToneTunerDesign.tint : ToneTunerDesign.primaryLabel) : ToneTunerDesign.secondaryLabel)
                        .frame(width: 10, height: 10)
                        .scaleEffect(!shouldReduceMotion && beat == metronome.currentBeat && metronome.isPlaying ? 1.15 : 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 33)
            Spacer(minLength: usesCompactControls ? 8 : 116)
            VStack(spacing: 0) {
                Text(tempoMarking).font(.system(size: 22)).foregroundStyle(ToneTunerDesign.secondaryLabel)
                Text("\(Int(tempo.rounded()))")
                    .font(.system(size: 128, weight: .bold, design: .rounded)).foregroundStyle(ToneTunerDesign.primaryLabel)
                    .shadow(color: ToneTunerDesign.primaryLabel.opacity(0.28), radius: 6, y: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .minimumScaleFactor(0.5)
            }
            .frame(height: 188)
            Spacer(minLength: usesCompactControls ? 12 : 24)
            controls
                .padding(.bottom, 11)
        }
        .padding(.horizontal, 11)
        .padding(.top, 21)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 36)
        .accessibilityElement(children: .ignore).accessibilityLabel("节拍器").accessibilityValue(metronomeAccessibilityValue)
    }

    @ViewBuilder private var controls: some View {
        if usesCompactControls {
            VStack(spacing: 11) {
                compactTempoControl
                signatureButton(height: 108)
                tapButton(height: 87)
            }
            .frame(maxWidth: .infinity, minHeight: 271, maxHeight: 271, alignment: .top)
        } else {
            GeometryReader { proxy in
            let controlWidth = proxy.size.width
            let endpointWidth = min(32, max(24, controlWidth * 0.088))
            let horizontalInset = min(16, max(8, controlWidth * 0.044))
            let sliderWidth = max(0, controlWidth - horizontalInset * 2 - endpointWidth * 2 - 24)
            let lowerRowWidth = max(0, controlWidth - 10)
            let signatureWidth = lowerRowWidth * 213 / 362
            let tapWidth = lowerRowWidth - signatureWidth

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ToneTunerDesign.secondaryLabel)
                        .frame(width: endpointWidth, height: 50)
                    Slider(value: $tempo, in: 40...240, step: 1)
                        .tint(ToneTunerDesign.tint)
                    .frame(width: sliderWidth, height: 50)
                    Image(systemName: "hare.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ToneTunerDesign.secondaryLabel)
                        .frame(width: endpointWidth, height: 50)
                }
                .padding(.horizontal, horizontalInset)
                .frame(width: controlWidth, height: 54)
                .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
                HStack(alignment: .top, spacing: 10) {
                    signatureButton(height: 87).frame(width: signatureWidth)
                    tapButton(height: 87).frame(width: tapWidth)
                }
            }
            }
            .frame(maxWidth: .infinity, minHeight: 151, maxHeight: 151)
        }
    }

    private var compactTempoControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "tortoise.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ToneTunerDesign.secondaryLabel)
                .frame(width: 32, height: 50)
            Slider(value: $tempo, in: 40...240, step: 1)
                .tint(ToneTunerDesign.tint)
                .frame(maxWidth: .infinity, minHeight: 50)
            Image(systemName: "hare.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ToneTunerDesign.secondaryLabel)
                .frame(width: 32, height: 50)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
    }

    private func signatureButton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("拍号").font(.system(size: 17)).foregroundStyle(ToneTunerDesign.primaryLabel)
            Spacer()
            Picker("拍号", selection: $beatsPerBar) {
                Text("2/4").tag(2); Text("3/4").tag(3); Text("4/4").tag(4); Text("6/8").tag(6)
            }.tint(ToneTunerDesign.tint).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 17).padding(.top, 11).padding(.bottom, 0)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
    }

    private func tapButton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("点击取拍").font(.system(size: 17)).foregroundStyle(ToneTunerDesign.primaryLabel)
            Spacer()
            Image(systemName: "hand.tap").font(.system(size: 24, weight: .semibold)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .gesture(tapOnTouchDown)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
        .accessibilityLabel("点击取拍")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { registerTap() }
    }

    @ViewBuilder private var statusView: some View {
        if metronome.state == .interrupted { recoveryRow("音频已中断，请重新开始。") }
        else if case .failed(let error) = metronome.state { recoveryRow(error.message) }
    }

    private func recoveryRow(_ text: String) -> some View {
        VStack(spacing: 8) { Label(text, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(ToneTunerDesign.secondaryLabel).multilineTextAlignment(.center); Button("重试") { metronome.start(tempo: engineTempo, beatsPerBar: beatsPerBar) } }
    }

    private var playButton: some View {
        Button(action: togglePlayback) {
            Text(metronome.isPlaying ? "停止" : "开始").font(.system(size: 28, weight: .bold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 73)
        }
        .buttonStyle(.plain).foregroundStyle(ToneTunerDesign.primaryLabel)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 37)
        .accessibilityHint("以当前速度播放节拍")
    }

    private var metronomeAccessibilityValue: String {
        if metronome.isPlaying { return String(format: String(localized: "每分钟 %1$ld 拍，第 %2$ld 拍，共 %3$ld 拍"), locale: .current, engineTempo, metronome.currentBeat + 1, metronome.activeBeatsPerBar) }
        return String(format: String(localized: "已停止，每分钟 %ld 拍"), locale: .current, engineTempo)
    }

    private func togglePlayback() { metronome.isPlaying ? metronome.stop() : metronome.start(tempo: engineTempo, beatsPerBar: beatsPerBar) }

    private func registerTap() {
        guard let candidate = tapTempo.registerTap(at: Date.timeIntervalSinceReferenceDate) else { return }
        tempo = Double(candidate)
    }

    private var tapOnTouchDown: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !hasRegisteredTapTouch else { return }
                hasRegisteredTapTouch = true
                registerTap()
            }
            .onEnded { _ in hasRegisteredTapTouch = false }
    }
}

struct MetronomePage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var metronome: MetronomeEngine
    @Binding var tempo: Double
    @Binding var beatsPerBar: Int
    let tap: () -> Void
    @State private var hasRegisteredTapTouch = false

    private var engineTempo: Int { Int(tempo.rounded()) }
    private var usesCompactControls: Bool { dynamicTypeSize.isAccessibilitySize }
    private var tempoMarking: LocalizedStringKey {
        switch engineTempo {
        case ..<80: "广板"
        case ..<120: "行板"
        case ..<160: "中板"
        case ..<200: "快板"
        default: "急板"
        }
    }

    var body: some View {
        displayPanel
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ToneTunerDesign.background)
    }

    private var displayPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(0..<metronome.activeBeatsPerBar, id: \.self) { beat in
                    Circle()
                        .fill(beat == metronome.currentBeat && metronome.isPlaying ? (beat == 0 ? ToneTunerDesign.tint : ToneTunerDesign.primaryLabel) : ToneTunerDesign.secondaryLabel)
                        .frame(width: 10, height: 10)
                        .scaleEffect(!reduceMotion && beat == metronome.currentBeat && metronome.isPlaying ? 1.15 : 1)
                }
            }
            .frame(height: 33)
            Spacer(minLength: usesCompactControls ? 8 : 116)
            VStack(spacing: 0) {
                Text(tempoMarking).font(.title2).foregroundStyle(ToneTunerDesign.secondaryLabel)
                Text("\(engineTempo)")
                    .font(.system(size: 128, weight: .bold, design: .rounded))
                    .foregroundStyle(ToneTunerDesign.primaryLabel)
                    .shadow(color: ToneTunerDesign.primaryLabel.opacity(0.28), radius: 6, y: 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .minimumScaleFactor(0.5)
            }
            .frame(height: 188)
            Spacer(minLength: usesCompactControls ? 12 : 24)
            controls.padding(.bottom, 11)
        }
        .padding(.horizontal, 11)
        .padding(.top, 21)
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 36)
    }

    @ViewBuilder private var controls: some View {
        if usesCompactControls {
            VStack(spacing: 11) {
                compactTempoControl
                signatureButton(height: 108)
                tapButton(height: 87)
            }
            .frame(maxWidth: .infinity, minHeight: 271, maxHeight: 271, alignment: .top)
        } else {
            VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
                    .frame(width: 32, height: 50)
                Slider(value: $tempo, in: 40...240, step: 1)
                    .tint(ToneTunerDesign.tint)
                .frame(maxWidth: .infinity, minHeight: 50)
                Image(systemName: "hare.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
                    .frame(width: 32, height: 50)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)

            GeometryReader { proxy in
                    let available = max(0, proxy.size.width - 10)
                    let signatureWidth = available * 213 / 352
                    let tapWidth = available - signatureWidth
                    HStack(alignment: .top, spacing: 10) {
                        signatureButton(height: 87).frame(width: signatureWidth)
                        tapButton(height: 87).frame(width: tapWidth)
                    }
                    .frame(width: proxy.size.width, height: 87)
            }
            .frame(height: 87)
            }
        }
    }

    private var compactTempoControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "tortoise.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ToneTunerDesign.secondaryLabel)
                .frame(width: 32, height: 50)
            Slider(value: $tempo, in: 40...240, step: 1)
                .tint(ToneTunerDesign.tint)
                .frame(maxWidth: .infinity, minHeight: 50)
            Image(systemName: "hare.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ToneTunerDesign.secondaryLabel)
                .frame(width: 32, height: 50)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
    }

    private func signatureButton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("拍号").font(.headline).foregroundStyle(ToneTunerDesign.primaryLabel)
            Spacer()
            Picker("拍号", selection: $beatsPerBar) {
                Text("2/4").tag(2); Text("3/4").tag(3); Text("4/4").tag(4); Text("6/8").tag(6)
            }
            .tint(ToneTunerDesign.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 17)
        .padding(.top, 11)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
    }

    private func tapButton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("点击取拍").font(.headline).foregroundStyle(ToneTunerDesign.primaryLabel)
            Spacer()
            Image(systemName: "hand.tap")
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .gesture(tapOnTouchDown)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
        .accessibilityLabel("点击取拍")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap() }
    }

    private var tapOnTouchDown: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !hasRegisteredTapTouch else { return }
                hasRegisteredTapTouch = true
                tap()
            }
            .onEnded { _ in hasRegisteredTapTouch = false }
    }
}
