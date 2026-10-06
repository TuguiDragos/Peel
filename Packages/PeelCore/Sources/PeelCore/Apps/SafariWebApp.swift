import Foundation

/// A web app Safari makes with File > Add to Dock (Apple, "Use Safari web apps on Mac"). Safari writes it as a
/// template of its own `com.apple.Safari.WebApp`, under an identifier that is the template's followed by the UUID it
/// gives the web app, so that identifier names this one web app and nothing else of Apple's.
enum SafariWebApp {
    static let template = "com.apple.Safari.WebApp"

    /// True when `info`, an app's Info.plist, is one Safari wrote for a web app named `identifier`.
    static func isOne(identifier: String, info: [String: Any]) -> Bool {
        guard
            info["LSTemplateApplication"] as? Bool == true,
            let parameters = info["LSTemplateApplicationParameters"] as? [String: Any],
            parameters["CFBundleIdentifier"] as? String == template,
            let uuid = parameters["TemplateAppUUID"] as? String
        else { return false }
        return identifier == template + "." + uuid && isIdentifier(identifier)
    }

    /// True for an identifier of the shape Safari gives a web app: its template, a dot, and a UUID.
    static func isIdentifier(_ identifier: String) -> Bool {
        guard identifier.count == template.count + 37 else { return false }
        let uuid = identifier.suffix(36)
        return identifier.lowercased().hasPrefix(template.lowercased() + ".") && UUID(uuidString: String(uuid)) != nil
    }

    /// The folder inside Safari's web app container where each web app gets a container named by its identifier.
    static func containers(inLibrary library: URL) -> URL {
        library.appending(path: "Containers/\(template)/Data/Library/Containers", directoryHint: .isDirectory)
    }
}
