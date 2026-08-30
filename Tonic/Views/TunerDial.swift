import SwiftUI
import Foundation

// 自绘组件：原生控件没有 cents 仪表。
struct PrecisionTunerGauge: View {
    let cents: Double?

    private var clampedCents: Double { min(max(cents ?? 0, -50), 50) }
    private var statusColor: Color {
        guard let cents else { return .secondary }
        return abs(cents) <= 5 ? .green : (abs(cents) <= 20 ? .orange : .red)
    }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.91)
            let radius = min(size.width * 0.45, size.height * 0.86)

            for tick in stride(from: -50, through: 50, by: 1) {
                let angle = Angle.degrees(270 + Double(tick) * 1.16)
                let isMajor = tick.isMultiple(of: 10)
                let isTarget = (-10...10).contains(tick)
                let outer = CGPoint(x: center.x + cos(angle.radians) * radius, y: center.y + sin(angle.radians) * radius)
                let tickLength: CGFloat = isMajor ? 20 : 11
                let inner = CGPoint(x: center.x + cos(angle.radians) * (radius - tickLength), y: center.y + sin(angle.radians) * (radius - tickLength))
                var mark = Path()
                mark.move(to: outer)
                mark.addLine(to: inner)
                let color: Color = isTarget ? .green : .blue.opacity(0.8)
                context.stroke(mark, with: .color(color), lineWidth: isMajor ? 3 : 1.5)
                if isMajor {
                    let labelPoint = CGPoint(x: center.x + cos(angle.radians) * (radius + 18), y: center.y + sin(angle.radians) * (radius + 18))
                    context.draw(Text("\(tick)").font(.caption2).foregroundStyle(color), at: labelPoint)
                }
            }

            let angle = Angle.degrees(270 + clampedCents * 1.2)
            let point = CGPoint(x: center.x + cos(angle.radians) * (radius - 36), y: center.y + sin(angle.radians) * (radius - 36))
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: point)
            context.stroke(needle, with: .color(cents == nil ? .secondary : .red), lineWidth: 5)
            let targetColor = cents.map { abs($0) <= 5 ? Color.green : statusColor } ?? .secondary
            context.fill(Path(ellipseIn: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)), with: .color(targetColor.opacity(0.9)))
            context.draw(Text(cents.map { String(format: "%+.0f", $0) } ?? "--").font(.title2.monospacedDigit()).foregroundStyle(.black), at: center)
        }
        .frame(height: 240)
        .dynamicTypeSize(.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音高偏差")
        .accessibilityValue(cents.map { String(format: "%+.0f 音分", $0) } ?? "等待声音")
        .animation(.linear(duration: 0.035), value: cents)
    }
}
