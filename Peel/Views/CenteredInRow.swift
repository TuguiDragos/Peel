import SwiftUI

extension View {
    /// A control alone in its box, centered in the row rather than left against one edge.
    func centeredInRow() -> some View {
        HStack {
            Spacer(minLength: 0)
            self
            Spacer(minLength: 0)
        }
    }
}
