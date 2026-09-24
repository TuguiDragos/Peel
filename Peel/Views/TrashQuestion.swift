import PeelCore
import SwiftUI

extension Text {
    /// The title of a Move to Trash confirmation: how many items, or which one, and how much space. Each title
    /// is one sentence, so a translation can reorder it. A dialog's title reaches AppKit with its inflection
    /// markup unresolved, so the markup is resolved here.
    static func movingToTrash(_ count: Int, _ total: SizeTotal) -> Text {
        let size = total.known.byteCount
        if total.known == 0 {
            return Text(verbatim: String(inflecting: "Move ^[\(count) item](inflect: true) to the Trash?"))
        }
        return Text(verbatim: total.isComplete
            ? String(inflecting: "Move ^[\(count) item](inflect: true) (\(size)) to the Trash?")
            : String(inflecting: "Move ^[\(count) item](inflect: true) (over \(size)) to the Trash?"))
    }

    static func movingToTrash(_ name: String, _ total: SizeTotal) -> Text {
        let size = total.known.byteCount
        if total.known == 0 {
            return Text("Move \(name) to the Trash?")
        }
        return total.isComplete
            ? Text("Move \(name) (\(size)) to the Trash?")
            : Text("Move \(name) (over \(size)) to the Trash?")
    }
}
