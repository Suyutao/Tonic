import SwiftUI

enum ToneTunerDesign {
    // These map to the adaptive iOS fills used by the Figma light and dark renders.
    static let background = Color(.systemBackground)
    static let backgroundElevated = Color(.secondarySystemBackground)
    static let backgroundElevatedSecondary = Color(.tertiarySystemBackground)
    static let backgroundElevatedTertiary = Color(.quaternarySystemFill)
    static let fillPrimary = Color(.systemFill)
    static let fillSecondary = Color(.secondarySystemFill)
    static let primaryLabel = Color(.label)
    static let secondaryLabel = Color(.secondaryLabel)
    static let tint = Color.accentColor
}

extension View {
    func toneTunerSurface(
        fill: Color = ToneTunerDesign.backgroundElevatedSecondary,
        stroke: Color = ToneTunerDesign.backgroundElevatedTertiary,
        cornerRadius: CGFloat = 26
    ) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
    }
}

struct TonicPrimaryButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            content
                .buttonStyle(.plain)
                .toneTunerSurface(fill: ToneTunerDesign.backgroundElevated, stroke: ToneTunerDesign.fillPrimary, cornerRadius: 37)
        }
    }
}

struct TonicToolbarButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
        }
    }
}

struct InlineLargeToolbar<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .kerning(0.4)
                .foregroundStyle(ToneTunerDesign.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 5)
            trailing()
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: 54)
        .background(ToneTunerDesign.background)
    }
}

struct LiquidGlassToolbarButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        label()
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(ToneTunerDesign.primaryLabel)
            .frame(width: 44, height: 44)
            .tint(ToneTunerDesign.primaryLabel)
            .modifier(LiquidGlassCircle())
    }
}

    private struct LiquidGlassCircle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.regularMaterial, in: Circle())
        }
    }
}
