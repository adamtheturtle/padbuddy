#if os(macOS)
    import SwiftUI

    /// Keeps the main window's dynamic toolbar out of AppKit's saved-frame
    /// restoration pass. The delegate opens the gate once launch has finished;
    /// windows opened later in the process mount their content immediately.
    @Observable
    final class WindowContentReadiness {
        static let shared = WindowContentReadiness()
        var isReady = false
    }

    struct WindowRestorationGate: ViewModifier {
        func body(content: Content) -> some View {
            if WindowContentReadiness.shared.isReady {
                content
            } else {
                Color.clear.frame(minHeight: 420)
            }
        }
    }
#endif
