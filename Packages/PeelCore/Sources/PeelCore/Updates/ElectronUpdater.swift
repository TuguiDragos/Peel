import Foundation

enum ElectronUpdater {
    static func feedURL(fromConfiguration text: String) -> URL? {
        let fields = topLevelFields(in: text)
        let file = "\(fields["channel"] ?? "latest")-mac.yml"

        switch fields["provider"] {
        case "generic":
            guard let base = fields["url"].flatMap(URL.init(string:)), base.scheme == "https" else { return nil }
            return base.appending(path: file)
        case "github":
            // A `host` other than github.com is a company's own server. The owner and repository were never meant
            // to leave that server, so they are not sent to github.com.
            guard fields["host"] == nil || fields["host"] == "github.com" else { return nil }
            guard let owner = fields["owner"], let repository = fields["repo"] else { return nil }
            return URL(string: "https://github.com/\(owner)/\(repository)/releases/latest/download/\(file)")
        default:
            return nil
        }
    }

    static func version(fromFeed text: String) -> String? {
        topLevelFields(in: text)["version"]
    }

    private static func topLevelFields(in text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) where line.first?.isWhitespace == false {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            if !key.isEmpty, !value.isEmpty {
                fields[key] = value
            }
        }
        return fields
    }
}
