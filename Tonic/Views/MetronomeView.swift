import SwiftUI


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
    private var controlsHeight: CGFloat { usesCompactControls ? 311 : 162 }
    private var minimumPanelHeight: CGFloat { 21 + 33 + 188 + controlsHeight }
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
        GeometryReader { proxy in
            Group {
                if usesCompactControls && proxy.size.height < minimumPanelHeight + 20 {
                    ScrollView(.vertical) {
                        displayPanel
                            .frame(height: minimumPanelHeight)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    displayPanel
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background(ToneTunerDesign.background)
        }
    }

    private var displayPanel: some View {
        GeometryReader { proxy in
            let availableGap = max(0, proxy.size.height - 21 - 33 - 188 - controlsHeight)
            let upperGap = availableGap * 0.382
            let lowerGap = availableGap * 0.618

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
                Color.clear.frame(height: upperGap)
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
                Color.clear.frame(height: lowerGap)
                controls.padding(.bottom, 11)
            }
            .padding(.horizontal, 11)
            .padding(.top, 21)
        }
        .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 36)
    }

    @ViewBuilder private var controls: some View {
        if usesCompactControls {
            VStack(spacing: 11) {
                compactTempoControl
                signatureButton(height: 112)
                tapButton(height: 112)
            }
            .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 300, alignment: .top)
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
            Text("拍号")
                .font(.headline)
                .foregroundStyle(ToneTunerDesign.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Picker("拍号", selection: $beatsPerBar) {
                Text("2/4").tag(2); Text("3/4").tag(3); Text("4/4").tag(4); Text("6/8").tag(6)
            }
            .tint(ToneTunerDesign.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 17)
        .padding(.top, 11)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .toneTunerSurface(stroke: ToneTunerDesign.fillSecondary, cornerRadius: 26)
    }

    private func tapButton(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("点击取拍")
                .font(.headline)
                .foregroundStyle(ToneTunerDesign.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Image(systemName: "hand.tap")
                .font(.system(size: 24, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
