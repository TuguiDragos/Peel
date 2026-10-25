import Foundation
internal import PeelPrivileged

/// A folder an app's own product file names for its data, given from the home.
public struct ProductFolder: Sendable, Hashable, Codable {
    /// Such as `.vscode-insiders` or `Library/Caches/JetBrains/IdeaIC2025.2`.
    public let path: String
    /// What the app writes inside once it has run, without which the folder is not taken as the app's. Nil for a
    /// folder whose name carries the app's release.
    public let proof: String?
    /// What inside holds the person's own work, such as a JetBrains IDE's scratch files and query consoles.
    public let work: [String]

    public init(path: String, proof: String?, work: [String] = []) {
        self.path = path
        self.proof = proof
        self.work = work
    }

    /// Whether `url` is this folder in `home` and holds its proof.
    func isFolder(at url: URL, home: String) -> Bool {
        let folder = URL(filePath: home, directoryHint: .isDirectory).appending(path: path)
        guard PathPattern.comparablePath(of: url).lowercased() == PathPattern.comparablePath(of: folder).lowercased()
        else { return false }
        return holdsProof(at: url)
    }

    /// Whether the folder at `url` holds its proof.
    func holdsProof(at url: URL) -> Bool {
        guard let proof else { return true }
        var info = stat()
        return lstat(url.appending(path: proof).path(percentEncoded: false), &info) == 0
    }

    /// Whether the folder at `url` holds anything in one of its `work` folders.
    func holdsWork(at url: URL) -> Bool {
        work.contains { name in
            let folder = url.appending(path: name).path(percentEncoded: false)
            return (try? FileManager.default.contentsOfDirectory(atPath: folder))?.isEmpty == false
        }
    }
}

/// The folders an app's own product file names for its data.
enum ProductFolders {
    /// What a JetBrains IDE's launcher reads to name its folders.
    static let jetBrainsFile = "Contents/Resources/product-info.json"
    /// What a code editor built on VS Code reads to name its folders.
    static let vsCodeFile = "Contents/Resources/app/product.json"

    static func of(appAt url: URL) -> [ProductFolder] {
        jetBrainsFolders(in: json(at: url.appending(path: jetBrainsFile))) + vsCodeFolders(in: vsCodeProduct(of: url))
    }

    /// Whether `folder`, read back from a file, is one these rules would name.
    static func believes(_ folder: ProductFolder) -> Bool {
        let names = PathComponents.of(folder.path)
        let named = switch names.count {
        case 4: jetBrainsFolders(in: ["productVendor": names[2], "dataDirectoryName": names[3]])
        case 3 where names[0] == "Library" && names[1] == "Application Support" && isOneName(names[2]):
            [vsCodeData(named: names[2])]
        case 1: vsCodeFolders(in: ["dataFolderName": names[0], "sharedDataFolderName": names[0]])
        default: [ProductFolder]()
        }
        return named.contains(folder)
    }

    static func vsCodeProduct(of app: URL) -> [String: Any]? {
        json(at: app.appending(path: vsCodeFile))
    }

    /// A JetBrains IDE keeps its settings, caches and logs in `<productVendor>/<dataDirectoryName>` inside
    /// Application Support, Caches and Logs. Only a data directory named with its release, such as `IdeaIC2025.2`, is
    /// believed: a plain name could be another product's folder.
    static func jetBrainsFolders(in product: [String: Any]?) -> [ProductFolder] {
        guard let vendor = product?["productVendor"] as? String, let name = product?["dataDirectoryName"] as? String,
              isOneName(vendor), isOneName(name), Naming.withoutAttachedVersion(name) != nil
        else { return [] }
        return [
            ProductFolder(path: "Library/Application Support/\(vendor)/\(name)", proof: nil, work: ["scratches", "consoles"]),
            ProductFolder(path: "Library/Caches/\(vendor)/\(name)", proof: nil),
            ProductFolder(path: "Library/Logs/\(vendor)/\(name)", proof: nil),
        ]
    }

    /// A code editor built on VS Code keeps its extensions in `~/<dataFolderName>`, beside the `argv.json` it writes
    /// there, what its windows share in `~/<sharedDataFolderName>/sharedStorage`, and the rest in
    /// `Application Support/<nameShort>`, with unsaved files in `Backups` and local history in `User/History`. Each
    /// folder is taken only while it holds what VS Code writes there.
    static func vsCodeFolders(in product: [String: Any]?) -> [ProductFolder] {
        let keys = [("dataFolderName", "argv.json"), ("sharedDataFolderName", "sharedStorage")]
        let home: [ProductFolder] = keys.compactMap { key, proof in
            guard let name = product?[key] as? String, name.hasPrefix("."), isOneName(String(name.dropFirst()))
            else { return nil }
            return ProductFolder(path: name, proof: proof)
        }
        guard product?["dataFolderName"] is String, let name = product?["nameShort"] as? String, isOneName(name)
        else { return home }
        return home + [vsCodeData(named: name)]
    }

    private static func vsCodeData(named name: String) -> ProductFolder {
        ProductFolder(
            path: "Library/Application Support/\(name)", proof: "User/globalStorage/storage.json",
            work: ["Backups", "User/History"]
        )
    }

    /// One plain name: not hidden, and nothing but letters, digits, spaces, `-`, `_` and `.`.
    private static func isOneName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".")
            && name.allSatisfy { $0.isLetter || $0.isNumber || " -_.".contains($0) }
    }

    private static func json(at url: URL) -> [String: Any]? {
        BoundedRead.data(at: url, maximum: 1_024 * 1_024).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
    }
}
