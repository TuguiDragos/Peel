import AppKit
import PeelCore
import SwiftUI

/// The widths of the kind and size columns in a removal row, measured from the strings themselves rather
/// than fixed.
///
/// A width chosen for English is wrong in other languages, and one measured at the regular weight is too
/// narrow once Bold Text is on. So each width is measured once, in the running language, at both weights.
@MainActor
enum RowColumns {
    /// The width of the widest kind a row can name, at the caption size rows use. The column fits every kind
    /// rather than cutting it, since several are macOS folder names the user knows from Finder.
    static let kind = widest(
        SearchLocation.Kind.allCases.map { String(localized: $0.title) },
        ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize
    )

    /// The width of "Unknown" or of the widest byte count, which depends on the locale's separators.
    static let size = widest(
        [String(localized: "Unknown")] + byteCounts,
        ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
        monospacedDigits: true
    )

    /// One of each shape a byte count takes, because the widest is not the largest: "100 bytes" is wider
    /// than any figure in gigabytes.
    private static let byteCounts: [String] = [
        100, 999, 999_999, 245_500_000, 1_073_741_824, 9_999_999_999, 999_999_999_999,
    ].map { Int64($0).byteCount }

    /// The widest of `strings` at the regular and the bold weight, plus a point. Bold Text is a system setting,
    /// and a column measured without it stops lining up when it is on. The bold system font stands in for what
    /// Bold Text draws, and it errs wide, which is safe for a column.
    private static func widest(_ strings: [String], ofSize size: CGFloat, monospacedDigits: Bool = false) -> CGFloat {
        let fonts = [NSFont.Weight.regular, .bold].map { weight in
            monospacedDigits
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
        }
        let width = strings.flatMap { text in
            fonts.map { (text as NSString).size(withAttributes: [.font: $0]).width }
        }.max() ?? 0
        return ceil(width) + 1
    }
}
