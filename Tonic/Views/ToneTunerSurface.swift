import SwiftUI

extension View {
    @ViewBuilder
    func toneTunerSurface(cornerRadius: CGFloat = 22) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
