// Checks a release of Peel on GitHub, a draft before it is published and the release once it is. Every copy of Peel
// reads the update feed of the latest release, and a published release can't be changed, so what went up is held to
// what release.sh made and checked.
//
// Usage: swift Scripts/check_release.swift <version> [<the folder release.sh made, build/Release>]
// Prints what the release offers, or each reason it is refused, and then exits 1. Reads GitHub through gh, signed in.
import CryptoKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard (1...2).contains(arguments.count) else {
    print("usage: swift check_release.swift <version> [<the folder release.sh made>]")
    exit(64)
}
let version = arguments[0]
let made = arguments.count == 2 ? URL(filePath: arguments[1], directoryHint: .isDirectory) : nil
let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let tag = "v\(version)"
let image = "Peel-\(version).dmg"
let archive = "Peel-\(version).zip"
let download = "https://github.com/TuguiDragos/Peel/releases/download/\(tag)/\(image)"
let latest = URL(string: "https://github.com/TuguiDragos/Peel/releases/latest/download/appcast.xml")!

/// What gh writes for `arguments`, or nil when it fails.
func gh(_ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/env")
    process.arguments = ["gh"] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
}

struct Release: Decodable {
    struct Asset: Decodable {
        let id: Int
        let name: String
        let size: Int
        let digest: String?
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
// Drafts are listed only to the account that can publish them, which is the one gh is signed in with.
guard let listed = gh(["api", "repos/TuguiDragos/Peel/releases?per_page=100"]),
      let releases = try? decoder.decode([Release].self, from: listed)
else {
    print("REFUSED: GitHub's list of releases can't be read through gh")
    exit(1)
}
guard let release = releases.first(where: { $0.tagName == tag }) else {
    print("REFUSED: no release, draft or published, carries the tag \(tag)")
    exit(1)
}

var refusals: [String] = []
func asset(_ name: String) -> Release.Asset? {
    let found = release.assets.first { $0.name == name }
    if found == nil { refusals.append("it has no \(name)") }
    return found
}
if release.prerelease { refusals.append("it is a prerelease, which is never the latest release") }
let feedAsset = asset("appcast.xml")
let imageAsset = asset(image)
let archiveAsset = asset(archive)

let feed = feedAsset.flatMap {
    gh(["api", "-H", "Accept: application/octet-stream", "repos/TuguiDragos/Peel/releases/assets/\($0.id)"])
}
if feedAsset != nil, feed == nil { refusals.append("its appcast.xml can't be read") }

// The key every copy checks with, as the project names it for both configurations.
let projectFile = repository.appending(path: "Peel.xcodeproj/project.pbxproj")
guard let key = (try? String(contentsOf: projectFile, encoding: .utf8))?
    .firstMatch(of: #/SPARKLE_PUBLIC_ED_KEY = "?([A-Za-z0-9+/=]+)"?;/#)
    .flatMap({ Data(base64Encoded: String($0.output.1)) })
    .flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) })
else {
    print("REFUSED: Peel.xcodeproj names no update key")
    exit(1)
}

/// The elements directly inside the feed's items, with their text and attributes.
final class Items: NSObject, XMLParserDelegate {
    var all: [[String: (text: String, attributes: [String: String])]] = []
    private var current: [String: (text: String, attributes: [String: String])]?
    private var depth = 0
    private var attributes: [String: String] = [:]
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if name == "item" {
            current = [:]
            depth = 0
        } else if current != nil {
            depth += 1
        }
        self.attributes = attributes
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item", let item = current {
            all.append(item)
            current = nil
        } else if current != nil {
            if depth == 1 { current?[name] = (text.trimmingCharacters(in: .whitespacesAndNewlines), attributes) }
            depth -= 1
        }
        text = ""
    }
}

if let feed {
    // Sparkle checks the signature over every byte before the feed's signature block (SPUExtractSignedFeed.m).
    if let block = feed.range(of: Data("<!-- sparkle-signatures:\n".utf8), options: .backwards) {
        let signed = feed[..<block.lowerBound]
        var fields: [String: String] = [:]
        for line in String(decoding: feed[block.upperBound...], as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 { fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
        }
        let verifies = fields["edSignature"].flatMap { Data(base64Encoded: $0) }
            .map { key.isValidSignature($0, for: Data(signed)) } ?? false
        if fields["length"] != String(signed.count) || !verifies {
            refusals.append("its feed's signature doesn't verify with the update key in Peel")
        }
    } else {
        refusals.append("its feed isn't signed, and Peel takes only a signed feed")
    }
    let items = Items()
    let parser = XMLParser(data: feed)
    parser.delegate = items
    if !parser.parse() { refusals.append("its feed isn't valid XML") }
    if items.all.count != 1 { refusals.append("its feed offers \(items.all.count) updates rather than one") }
    if let item = items.all.first {
        let offered = item["sparkle:shortVersionString"]?.text ?? "nothing"
        if offered != version { refusals.append("its feed offers version \(offered), not \(version)") }
        let enclosure = item["enclosure"]?.attributes ?? [:]
        if enclosure["url"] != download {
            refusals.append("its feed downloads \(enclosure["url"] ?? "nothing"), not \(download)")
        }
        if let imageAsset, enclosure["length"] != String(imageAsset.size) {
            refusals.append("its feed gives a length other than \(image)'s, \(imageAsset.size) bytes")
        }
    }
}

// What went up is what release.sh made: the feed it checked, byte for byte, and the files by their SHA-256.
if let made {
    if let feed, (try? Data(contentsOf: made.appending(path: "feed/appcast.xml"))) != feed {
        refusals.append("its appcast.xml isn't the one in \(made.path(percentEncoded: false))feed")
    }
    for case let (name, uploaded?) in [(image, imageAsset), (archive, archiveAsset)] {
        guard let local = try? Data(contentsOf: made.appending(path: name)) else {
            refusals.append("\(made.path(percentEncoded: false)) has no \(name) to compare")
            continue
        }
        let digest = "sha256:" + SHA256.hash(data: local).map { String(format: "%02x", $0) }.joined()
        if let kept = uploaded.digest {
            if kept != digest { refusals.append("its \(name) isn't the one release.sh made") }
        } else if uploaded.size != local.count {
            refusals.append("its \(name) is not the size of the one release.sh made")
        }
    }
}

// Once published, the address every copy asks must lead to this very feed, over HTTPS alone.
if !release.draft, let feed {
    let answer = try? await URLSession.shared.data(from: latest)
    if answer?.1.url?.scheme != "https" || answer?.0 != feed {
        refusals.append("the latest release's appcast.xml, which every copy reads, isn't this release's")
    }
}

if refusals.isEmpty {
    let state = release.draft ? "draft" : "published release"
    let source = made == nil ? "" : ", the ones release.sh made"
    print("The \(state) \(tag) holds \(image), \(archive), and appcast.xml\(source).")
    print("Its feed is signed with the update key in Peel and offers Peel \(version) from \(download).")
    if !release.draft { print("The latest release serves that feed.") }
} else {
    for refusal in refusals { print("REFUSED: the release \(tag): \(refusal).") }
    exit(1)
}
