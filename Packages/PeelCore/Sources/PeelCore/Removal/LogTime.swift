import Foundation

/// How History's logs write a time: ISO 8601 to the millisecond, since one removal moves every part within a
/// second and names them in the order they moved. A time written to the second reads as well.
enum LogTime {
    static let encoding = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(text(for: date))
    }

    /// `date` to the nearest millisecond, as the logs write it. The digits come from whole milliseconds rather
    /// than from the formatter, which cuts the fraction: a time read back from a log is a hair under what was
    /// written, so cut, it would lose a millisecond each time the log is written again.
    static func text(for date: Date) -> String {
        let total = (date.timeIntervalSince1970 * 1_000).rounded()
        let seconds = (total / 1_000).rounded(.down)
        let fraction = String(format: "%03d", Int(total - seconds * 1_000))
        return "\(Date(timeIntervalSince1970: seconds).formatted(.iso8601).dropLast()).\(fraction)Z"
    }

    static let decoding = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = (try? Date(text, strategy: milliseconds)) ?? (try? Date(text, strategy: .iso8601)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 time.")
        }
        return date
    }

    private static let milliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
