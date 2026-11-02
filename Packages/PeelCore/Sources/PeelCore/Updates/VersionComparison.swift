import Foundation

enum VersionComparison {
    /// True when `text` begins with a number, as a version does. A release's name, or anything else, is no version.
    static func isAVersion(_ text: String) -> Bool {
        !components(of: text).numbers.isEmpty
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    /// True when `candidate` has as many numbers as `installed` and they are past its numbers. A version written with
    /// another number of them, such as one with a build added as a fourth, and what follows the numbers, a build or a
    /// word such as beta, are not compared, since makers write them in ways another source of versions doesn't follow.
    static func hasNewerNumbers(_ candidate: String, than installed: String) -> Bool {
        let candidate = components(of: candidate).numbers
        let installed = components(of: installed).numbers
        return candidate.count == installed.count && compare(numbers: candidate, installed) == .orderedDescending
    }

    /// Compares dotted numeric versions. A version with a suffix ("1.2 beta") is older than the same version
    /// without one.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = components(of: lhs)
        let right = components(of: rhs)

        let numbers = compare(numbers: left.numbers, right.numbers)
        guard numbers == .orderedSame else { return numbers }

        switch (left.suffix.isEmpty, right.suffix.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): return left.suffix.compare(right.suffix, options: .numeric)
        }
    }

    private static func compare(numbers left: [Int], _ right: [Int]) -> ComparisonResult {
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(of version: String) -> (numbers: [Int], suffix: String) {
        var text = Substring(version.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" {
            text = text.dropFirst()
        }
        // Build metadata (`1.2.3+45`) and a build in parentheses (`1.2.3 (456)`) say nothing about which is newer.
        if let cut = text.firstIndex(where: { $0 == "+" || $0 == "(" }) {
            text = text[..<cut]
        }
        let coreEnd = text.firstIndex { !($0.isASCII && ($0.isNumber || $0 == ".")) } ?? text.endIndex
        // A component too large for `Int` counts as the largest value. Dropping it would shift the rest one place left.
        let numbers = text[..<coreEnd].split(separator: ".").map { Int($0) ?? .max }
        let suffix = text[coreEnd...].trimmingCharacters(in: CharacterSet(charactersIn: " -+._"))
        return (numbers, suffix)
    }
}
