import Foundation

/// How History's logs write a time: ISO 8601 to the millisecond, since one removal moves every part within a
/// second and names them in the order they moved. A time written to the second reads as well.
enum LogTime {
    static let encoding = JSONEncoder.DateEncodingStrategy.custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(date.formatted(milliseconds))
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
