import SwiftUI

extension View {
    /// Makes the view at least 20 by 20 points, the smallest control size the HIG gives for the Mac, and makes
    /// that whole area clickable. Use it on a button whose label draws smaller, such as a borderless button's text.
    func minimumTarget() -> some View {
        frame(minWidth: 20, minHeight: 20)
            .contentShape(.rect)
    }
}
