import Foundation

enum AppStoreLookup {
    enum Answer: Equatable {
        /// The Mac app's version, its store page (where the user can read what changed and update), and its
        /// developer as `artistName` gives it ("Apple" for Apple's own apps, where `sellerName` gives "Apple Inc.").
        case mac(version: String, page: URL?, developer: String?)
        /// Apple answered, but with no Mac record. An app sold as one purchase for iPhone, iPad, and Mac has a
        /// single record of kind "software" that carries the iPhone version, which cannot be compared with the
        /// Mac app's. Apple also answers with no record at all for an app the store doesn't sell in this region,
        /// or doesn't sell anymore. Neither is a failed lookup.
        case noMacRecord
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

    static func answer(in data: Data) -> Answer {
        guard let results = (try? JSONDecoder().decode(Response.self, from: data))?.results else { return .unreadable }
        guard let mac = results.first(where: { $0.kind == "mac-software" }), let version = mac.version else { return .noMacRecord }
        return .mac(
            version: version,
            page: mac.trackViewUrl.flatMap(URL.init(string:)),
            developer: mac.artistName.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let kind: String?
            let version: String?
            let trackViewUrl: String?
            let artistName: String?
        }

        let results: [Result]
    }
}
