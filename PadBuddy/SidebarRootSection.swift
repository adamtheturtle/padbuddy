import SwiftUI

#if os(macOS)
    /// An untitled native Section inserts an unnamed accessibility header row.
    typealias SidebarRootSection<Content: View> = Group<Content>
#else
    struct SidebarRootSection<Content: View>: View {
        let content: Content

        init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        var body: some View {
            Section { content }
        }
    }
#endif
