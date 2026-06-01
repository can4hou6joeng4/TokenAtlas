import SwiftUI

extension View {
    /// Shared main-window panel chrome: the same rounded card treatment used by
    /// wide Dashboard/Usage-style pages.
    func mainWindowPanel(padding: CGFloat = 14) -> some View {
        appSurface(.mainWindowCard, padding: padding)
    }

    /// Main-window panel chrome that lets the surface itself fill a parent
    /// layout's height proposal, used for visually equal-height panel pairs.
    func fillingMainWindowPanel(padding: CGFloat = 14) -> some View {
        fillingAppSurface(.mainWindowCard, padding: padding)
    }
}
