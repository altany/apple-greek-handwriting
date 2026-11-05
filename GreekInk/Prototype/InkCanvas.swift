import SwiftUI

/// SwiftUI wrapper around the shared UIKit canvas. The view model owns the UIKit view
/// so it can read strokes and clear them.
struct InkCanvas: UIViewRepresentable {
    let view: InkCanvasView

    func makeUIView(context: Context) -> InkCanvasView { view }
    func updateUIView(_ uiView: InkCanvasView, context: Context) {}
}
