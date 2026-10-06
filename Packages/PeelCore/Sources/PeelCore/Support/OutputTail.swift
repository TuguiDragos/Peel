public import Foundation

/// The end of a tool's output, as a page shows it while the tool runs.
public enum OutputTail {
    /// The last `count` lines of `output`, read back from its end, so the cost is the tail's however long the
    /// output has grown.
    public static func lastLines(of output: Data, count: Int) -> String {
        let newline = UInt8(ascii: "\n")
        var start = output.endIndex
        var found = 0
        while start > output.startIndex {
            let before = output.index(before: start)
            if output[before] == newline {
                found += 1
                if found == count { break }
            }
            start = before
        }
        return String(decoding: output[start...], as: UTF8.self)
    }
}
