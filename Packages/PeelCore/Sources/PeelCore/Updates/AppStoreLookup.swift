import Foundation

enum AppStoreLookup {
    enum Answer: Equatable {
        /// The listing's version, its store page (where the user can read what changed and update), its developer
        /// as `artistName` gives it ("Apple" for Apple's own apps, where `sellerName` gives "Apple Inc."), and what
        /// is new in that version, as plain text.
        case listed(version: String, page: URL?, developer: String?, notes: ReleaseNotes? = nil)
        /// Apple answered, but with no record of the listing asked, as for an app the store doesn't sell in this
        /// region, or doesn't sell anymore. That is not a failed lookup.
        case notListed
        case unreadable
    }

    static func url(bundleIdentifier: String, country: String, for listing: AppStoreListing) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        let asked = if case .iPhoneAndiPad(let item?, _) = listing {
            URLQueryItem(name: "id", value: String(item))
        } else {
            URLQueryItem(name: "bundleId", value: bundleIdentifier)
        }
        components?.queryItems = [asked, URLQueryItem(name: "country", value: country)]
        if listing == .mac {
            components?.queryItems?.append(URLQueryItem(name: "entity", value: "desktopSoftware"))
        }
        return components?.url
    }

    static func answer(in data: Data, for listing: AppStoreListing) -> Answer {
        guard let results = (try? JSONDecoder().decode(Response.self, from: data))?.results else { return .unreadable }
        let isListed: (Response.Result) -> Bool = switch listing {
        case .mac: { $0.kind == "mac-software" || ($0.kind == "software" && $0.namesOnlyTheMac) }
        case .iPhoneAndiPad(let item, _): { $0.kind == "software" && (item == nil || $0.trackId == item) }
        }
        guard let record = results.first(where: isListed), let version = record.version else { return .notListed }
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
            let trackId: Int?
            let version: String?
            let trackViewUrl: String?
            let artistName: String?
            let releaseNotes: String?
            let supportedDevices: [String]?

            /// An app sold once for iPhone, iPad, and Mac answers the desktop question with a record of kind
            /// "software" for the Mac alone, whose version can differ from the iPhone's.
            var namesOnlyTheMac: Bool {
                guard let devices = supportedDevices, devices.contains("MacDesktop-MacDesktop") else { return false }
                return !devices.contains { $0.hasPrefix("iPhone") || $0.hasPrefix("iPad") || $0.hasPrefix("iPod") }
            }
        }

        let results: [Result]
    }
}
