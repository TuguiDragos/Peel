import SwiftUI

extension View {
    /// Keeps a detail page's name on one line: it first shrinks a little, then is cut in the middle. Otherwise
    /// a name that is one long word, such as an identifier or a file name, breaks onto a second line.
    func titleLine() -> some View {
        lineLimit(1)
            .minimumScaleFactor(0.7)
            .truncationMode(.middle)
    }
}
