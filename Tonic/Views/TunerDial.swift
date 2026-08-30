import SwiftUI

struct TunerNoteChange: Equatable, Identifiable {
    let index: Int
    let name: String

    var id: Int { index }
}

struct TunerHistoryGraph: View {
    let values: [Double]
    var noteChanges: [TunerNoteChange] = []

    private let labels = [40, 30, 20, 10, 5, 0, -5, -10, -20, -30, -40]
    private let annotationBandHeight = CGFloat(28)
    private let graphPadding = CGFloat(8)

    var body: some View {
        GeometryReader { proxy in
            let curveInset = CGFloat(30)
            let graphWidth = max(proxy.size.width - curveInset, 1)
            let graphHeight = proxy.size.height

            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let curveTop = annotationBandHeight + graphPadding
                let curveBottom = max(curveTop, size.height - graphPadding)
                let zeroY = (curveTop + curveBottom) / 2
                var zeroPath = Path()
                zeroPath.move(to: CGPoint(x: curveInset, y: zeroY))
                zeroPath.addLine(to: CGPoint(x: size.width, y: zeroY))
                context.stroke(zeroPath, with: .color(ToneTunerDesign.secondaryLabel), lineWidth: 1)

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
                    curveInset: curveInset,
                    graphWidth: graphWidth
                )
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
        let normalized = min(max(value, -40), 40) / 40
        let y = zeroY - CGFloat(normalized) * curveHeight / 2
        return CGPoint(x: x, y: y)
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
        curveInset: CGFloat,
        graphWidth: CGFloat
    ) {
        var rowEnd = [curveInset, curveInset]
        for change in changes.sorted(by: { $0.index < $1.index }) where change.index >= 0 && change.index < values.count {
            let label = context.resolve(
                Text(change.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ToneTunerDesign.secondaryLabel)
            )
            let labelSize = label.measure(in: size)
            let plottedX = curveInset + graphWidth * CGFloat(change.index) / CGFloat(max(values.count - 1, 1))
            let x = min(max(plottedX, curveInset + labelSize.width / 2), size.width - labelSize.width / 2)
            let leading = x - labelSize.width / 2

            guard let row = rowEnd.indices.first(where: { leading >= rowEnd[$0] + 4 }) else { continue }
            context.draw(label, at: CGPoint(x: x, y: 2 + CGFloat(row) * 13), anchor: .top)
            rowEnd[row] = x + labelSize.width / 2
        }
    }
}
