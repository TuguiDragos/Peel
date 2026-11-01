import SwiftUI

extension View {
    /// A control alone in its box, centered in the row rather than left against one edge.
    func centeredInRow() -> some View {
        ActionRow { self }
    }
}
