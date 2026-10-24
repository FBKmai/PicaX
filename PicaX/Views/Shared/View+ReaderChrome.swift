import SwiftUI

extension View {
    @ViewBuilder
    func picaxReaderChrome(hidesNavigationBar: Bool, hidesStatusBar: Bool) -> some View {
        #if os(iOS)
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(hidesNavigationBar ? .hidden : .visible, for: .navigationBar, .bottomBar)
                .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
                .toolbar(hidesNavigationBar ? .hidden : .visible, for: .navigationBar, .bottomBar)
                .statusBarHidden(hidesStatusBar)
                .persistentSystemOverlays(hidesStatusBar ? .automatic : .visible)
        } else {
            self
                .navigationBarHidden(hidesNavigationBar)
                .statusBarHidden(hidesStatusBar)
        }
        #else
        self
        #endif
    }
}
