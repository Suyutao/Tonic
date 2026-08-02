import SwiftUI
import XCTest
import UIKit
@testable import Tone_Tuner

@MainActor
final class VisualRenderTests: XCTestCase {
    func testRenderRepresentativeTunerStates() throws {
        try render(
            TunerView()
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large),
            name: "tuner-standard-light"
        )

        try render(
            TunerView()
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-accessibility-dark",
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            TunerView()
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-landscape-english",
            size: CGSize(width: 874, height: 402)
        )
    }

    func testRenderRepresentativeMetronomeStates() throws {
        try render(
            MetronomeView()
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large),
            name: "metronome-standard-english"
        )

        try render(
            MetronomeView()
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-accessibility-dark",
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            MetronomeView(reduceMotionOverride: true)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-landscape-english-reduce-motion",
            size: CGSize(width: 874, height: 402)
        )
    }

    private func render<Content: View>(
        _ content: Content,
        name: String,
        size: CGSize = CGSize(width: 402, height: 874),
        traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .light)
    ) throws {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: content.frame(width: size.width, height: size.height))
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        var renderedImage: UIImage?
        traits.performAsCurrent {
            let renderer = UIGraphicsImageRenderer(size: size)
            renderedImage = renderer.image { context in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
        }
        guard let image = renderedImage, let data = image.pngData() else {
            XCTFail("Failed to render \(name)")
            return
        }
        XCTAssertGreaterThan(data.count, 10_000, "Rendered image appears blank")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
