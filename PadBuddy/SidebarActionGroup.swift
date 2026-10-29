import SwiftUI

#if os(macOS)
    /// A Group stays transparent to List, giving each action its own native row.
    typealias SidebarActionGroup<Content: View> = Group<Content>
#else
    struct SidebarActionGroup<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            VStack(spacing: 2) { content }
        }
    }
#endif
