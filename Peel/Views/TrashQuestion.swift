import PeelCore
import SwiftUI

extension Text {
    /// The title of a Move to Trash confirmation: how many items, or which one, and how much space. Each title
    /// is one sentence, so a translation can reorder it. A dialog's title reaches AppKit with its inflection
    /// markup unresolved, so the markup is resolved here.
    static func movingToTrash(_ count: Int, _ total: SizeTotal) -> Text {
        let size = total.known.byteCount
        return switch total.reading {
        case .exactly(0):
            Text(verbatim: String(inflecting: "Move ^[\(count) item](inflect: true) to the Trash?"))
        case .exactly:
            Text(verbatim: String(inflecting: "Move ^[\(count) item](inflect: true) (\(size)) to the Trash?"))
        case .atLeast:
            Text(verbatim: String(inflecting: "Move ^[\(count) item](inflect: true) (over \(size)) to the Trash?"))
        case .unknown:
            Text(verbatim: String(inflecting: "Move ^[\(count) item](inflect: true) (size unknown) to the Trash?"))
        }
    }

    static func movingToTrash(_ name: String, _ total: SizeTotal) -> Text {
        switch total.reading {
        case .exactly(0): Text("Move \(name) to the Trash?")
        case .exactly(let size): Text("Move \(name) (\(size.byteCount)) to the Trash?")
        case .atLeast(let size): Text("Move \(name) (over \(size.byteCount)) to the Trash?")
        case .unknown: Text("Move \(name) (size unknown) to the Trash?")
        }
    }
}
