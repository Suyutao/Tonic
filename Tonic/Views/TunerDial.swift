import SwiftUI

struct TunerNoteChange: Equatable, Identifiable {
    let index: Int
    let name: String

    var id: Int { index }
}

struct TunerHistoryGraph: View {
    let values: [Double]
    var noteChanges: [TunerNoteChange] = []

    private let labels = [25, 20, 15, 10, 5, 0, -5, -10, -15, -20, -25]

    var body: some View {
        GeometryReader { proxy in
            let curveInset = CGFloat(30)
            let graphWidth = max(proxy.size.width - curveInset, 1)
            let graphHeight = proxy.size.height

            Canvas { context, size in
                let zeroY = size.height / 2
                var zeroPath = Path()
                zeroPath.move(to: CGPoint(x: curveInset, y: zeroY))
                zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
                context.stroke(zeroPath, with: .color(ToneTunerDesign.secondaryLabel), lineWidth: 1)

                guard values.count > 1 else { return }
                var history = Path()
                for (index, value) in values.enumerated() {
                    let x = curveInset + graphWidth * CGFloat(index) / CGFloat(values.count - 1)
                    let normalized = min(max(value, -25), 25) / 25
                    let y = zeroY - CGFloat(normalized) * (size.height / 2 - 8)
                    if index == 0 || noteChanges.contains(where: { $0.index == index }) {
                        history.move(to: CGPoint(x: x, y: y))
                    } else {
                        history.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(history, with: .color(.white), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
            .overlay(alignment: .topLeading) {
                ForEach(noteChanges) { change in
                    let x = curveInset + graphWidth * CGFloat(min(max(change.index, 0), max(values.count - 1, 0))) / CGFloat(max(values.count - 1, 1))
                    Text(change.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ToneTunerDesign.secondaryLabel)
                        .position(x: x, y: 8)
                }
            }
            .overlay(alignment: .leading) {
                VStack(spacing: 0) {
                    ForEach(labels, id: \.self) { label in
                        Text(label == 0 ? "" : String(format: "%+d", label))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 138 / 255, green: 138 / 255, blue: 138 / 255))
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .frame(width: 30, height: graphHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音高偏差轨迹")
        .accessibilityValue(values.last.map { String(format: "%+.0f 音分", $0) } ?? "等待声音")
    }
}
