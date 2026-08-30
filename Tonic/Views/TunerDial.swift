import SwiftUI

struct TunerNoteChange: Equatable, Identifiable {
    let index: Int
    let name: String

    var id: Int { index }

    func shifted(leftBy count: Int) -> TunerNoteChange? {
        guard index >= count else { return nil }
        return TunerNoteChange(index: index - count, name: name)
    }
}

struct TunerHistoryGraph: View {
    let values: [Double]
    var noteChanges: [TunerNoteChange] = []

    private let labels = [40, 30, 20, 10, 0, -10, -20, -30, -40]
    var body: some View {
        GeometryReader { _ in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let axisLabel = context.resolve(
                    Text("+40")
                        .font(.system(size: 11))
                        .foregroundStyle(ToneTunerDesign.secondaryLabel)
                )
                let axisLabelSize = axisLabel.measure(in: size)
                let curveInset = axisLabelSize.width + 4
                let graphWidth = max(size.width - curveInset, 1)
                let curveTop = axisLabelSize.height / 2
                let curveBottom = max(curveTop, size.height - axisLabelSize.height / 2)
                let zeroY = (curveTop + curveBottom) / 2
                var zeroPath = Path()
                zeroPath.move(to: CGPoint(x: curveInset, y: zeroY))
                zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
                context.stroke(zeroPath, with: .color(ToneTunerDesign.secondaryLabel), lineWidth: 1)

                for labelValue in labels {
                    let label = context.resolve(
                        Text(String(format: "%+d", labelValue))
                            .font(.system(size: 11))
                            .foregroundStyle(ToneTunerDesign.secondaryLabel)
                    )
                    context.draw(
                        label,
                        at: CGPoint(
                            x: axisLabelSize.width / 2,
                            y: graphY(for: Double(labelValue), zeroY: zeroY, curveHeight: curveBottom - curveTop)
                        ),
                        anchor: .center
                    )
                }

                guard values.count > 1 else { return }
                let points = values.enumerated().map { index, value in
                    graphPoint(
                        index: index,
                        value: value,
                        count: values.count,
                        curveInset: curveInset,
                        graphWidth: graphWidth,
                        zeroY: zeroY,
                        curveHeight: curveBottom - curveTop
                    )
                }

                let transitionIndices = Set(noteChanges.map(\.index).filter { $0 > 0 && $0 < points.count })
                var segmentStart = 0
                for segmentEnd in transitionIndices.sorted() + [points.count] {
                    let segment = Array(points[segmentStart..<segmentEnd])
                    if segment.count > 1 {
                        context.stroke(
                            smoothPath(through: segment),
                            with: .color(ToneTunerDesign.primaryLabel),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    segmentStart = segmentEnd
                }

                drawAnnotations(
                    noteChanges,
                    context: &context,
                    size: size,
                    points: points
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音高偏差轨迹")
        .accessibilityValue(values.last.map { String(format: "%+.0f 音分", $0) } ?? "等待声音")
    }

    private func graphPoint(
        index: Int,
        value: Double,
        count: Int,
        curveInset: CGFloat,
        graphWidth: CGFloat,
        zeroY: CGFloat,
        curveHeight: CGFloat
    ) -> CGPoint {
        let x = curveInset + graphWidth * CGFloat(index) / CGFloat(max(count - 1, 1))
        let y = graphY(for: value, zeroY: zeroY, curveHeight: curveHeight)
        return CGPoint(x: x, y: y)
    }

    private func graphY(for value: Double, zeroY: CGFloat, curveHeight: CGFloat) -> CGFloat {
        let normalized = min(max(value, -40), 40) / 40
        return zeroY - CGFloat(normalized) * curveHeight / 2
    }

    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        for index in 0..<(points.count - 1) {
            let previous = points[max(index - 1, 0)]
            let current = points[index]
            let next = points[index + 1]
            let following = points[min(index + 2, points.count - 1)]
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (following.x - current.x) / 6,
                y: next.y - (following.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        return path
    }

    private func drawAnnotations(
        _ changes: [TunerNoteChange],
        context: inout GraphicsContext,
        size: CGSize,
        points: [CGPoint]
    ) {
        for change in changes where change.index >= 0 && change.index < points.count {
            let label = context.resolve(
                Text(change.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
            )
            let labelSize = label.measure(in: size)
            let point = points[change.index]
            let x = min(max(point.x + labelSize.width / 2 + 4, labelSize.width / 2), size.width - labelSize.width / 2)
            let y = min(max(point.y - labelSize.height / 2 - 6, labelSize.height / 2), size.height - labelSize.height / 2)
            context.draw(label, at: CGPoint(x: x, y: y), anchor: .center)
        }
    }
}
