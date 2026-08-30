import SwiftUI
import XCTest
import UIKit
@testable import Tonic

@MainActor
final class VisualRenderTests: XCTestCase {
    func testRenderTunerHistoryAnnotations() throws {
        let values = (0..<120).map { Double(($0 * 13) % 80 - 40) }
        let changes = [
            TunerNoteChange(index: 18, name: "A3"),
            TunerNoteChange(index: 61, name: "C♯4"),
            TunerNoteChange(index: 99, name: "E4")
        ]

        try render(
            TunerHistoryGraph(values: values, noteChanges: changes)
                .padding(12)
                .background(ToneTunerDesign.background)
                .environment(\.colorScheme, .dark),
            name: "tuner-history-annotations-dark",
            size: CGSize(width: 402, height: 186)
        )
    }

    func testRenderRepresentativeTunerStates() throws {
        try render(
            ContentView(initialPage: 0)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large),
            name: "tuner-standard-light"
        )

        try render(
            ContentView(initialPage: 0)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-accessibility-dark",
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            ContentView(initialPage: 0)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-iphonese-accessibility-dark",
            size: CGSize(width: 375, height: 667),
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            ContentView(initialPage: 0)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-landscape-english",
            size: CGSize(width: 874, height: 402)
        )

        try render(
            ContentView(initialPage: 0)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "tuner-iphone12pro-accessibility-dark",
            size: CGSize(width: 390, height: 844),
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )
    }

    func testRenderRepresentativeMetronomeStates() throws {
        try render(
            ContentView(initialPage: 1)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large),
            name: "metronome-standard-english"
        )

        try render(
            ContentView(initialPage: 1)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-accessibility-dark",
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            ContentView(initialPage: 1)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-iphonese-accessibility-dark",
            size: CGSize(width: 375, height: 667),
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
        )

        try render(
            ContentView(initialPage: 1)
                .environment(\.locale, Locale(identifier: "en"))
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-landscape-english",
            size: CGSize(width: 874, height: 402)
        )

        try render(
            ContentView(initialPage: 1)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .environment(\.dynamicTypeSize, .accessibility5),
            name: "metronome-iphone12pro-accessibility-dark",
            size: CGSize(width: 390, height: 844),
            traits: UITraitCollection { traits in
                traits.userInterfaceStyle = .dark
                traits.accessibilityContrast = .high
            }
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
