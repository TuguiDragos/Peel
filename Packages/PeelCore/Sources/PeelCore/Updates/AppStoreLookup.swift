import Foundation

enum AppStoreLookup {
    enum Answer: Equatable {
        /// The listing's version, its store page (where the user can read what changed and update), its developer
        /// as `artistName` gives it ("Apple" for Apple's own apps, where `sellerName` gives "Apple Inc."), and what
        /// is new in that version, as plain text.
        case listed(version: String, page: URL?, developer: String?, notes: ReleaseNotes? = nil)
        /// Apple answered, but with no record of the listing asked. An app sold as one purchase for iPhone, iPad,
        /// and Mac answers the Mac's question with a single record of kind "software" that carries the iPhone
        /// version, which cannot be compared with the Mac app's. Apple also answers with no record at all for an
        /// app the store doesn't sell in this region, or doesn't sell anymore. Neither is a failed lookup.
        case notListed
        case unreadable
    }

    static func url(bundleIdentifier: String, country: String) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier),
            URLQueryItem(name: "country", value: country),
        ]
        return components?.url
    }

    static func answer(in data: Data, for listing: AppStoreListing) -> Answer {
        guard let results = (try? JSONDecoder().decode(Response.self, from: data))?.results else { return .unreadable }
        let kind = switch listing {
        case .mac: "mac-software"
        case .iPhoneAndiPad: "software"
        }
        guard let record = results.first(where: { $0.kind == kind }), let version = record.version else {
            return .notListed
        }
        return .listed(
            version: version,
            page: record.trackViewUrl.flatMap(URL.init(string:)),
            developer: record.artistName.flatMap { $0.isEmpty ? nil : $0 },
            notes: record.releaseNotes.flatMap { ReleaseNotes($0, format: .plainText) }
        )
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let kind: String?
            let version: String?
            let trackViewUrl: String?
            let artistName: String?
            let releaseNotes: String?
        }

        let results: [Result]
    }
}
