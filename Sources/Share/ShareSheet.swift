import SwiftUI
import UIKit

/// The system share sheet for a rendered card.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// A rendered card waiting for the share sheet (`.sheet(item:)` needs an id).
struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Draws a card view to a UIImage at 3x, so a 390 x 693 pt card lands at
/// 1170 x 2079 px. ImageRenderer draws outside the window: the view must
/// take plain values, never an environment object.
enum CardRenderer {
    @MainActor
    static func image<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
