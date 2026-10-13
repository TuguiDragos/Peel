// Checks the update feed a release makes before it is published: every copy of Peel reads the feed of the latest
// release, so a feed that is wrong reaches all of them.
//
// Usage: swift Scripts/check_appcast.swift <appcast.xml> <Peel.app> <disk image> <download URL prefix>
// Prints what the feed offers, or each reason it is refused, and then exits 1.
import CryptoKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 4 else {
    print("usage: swift check_appcast.swift <appcast.xml> <Peel.app> <disk image> <download URL prefix>")
    exit(64)
}
let image = URL(filePath: arguments[2])
let download = arguments[3] + image.lastPathComponent

guard let info = NSDictionary(contentsOf: URL(filePath: arguments[1]).appending(path: "Contents/Info.plist")),
      let version = info["CFBundleShortVersionString"] as? String,
      let build = info["CFBundleVersion"] as? String,
      let minimum = info["LSMinimumSystemVersion"] as? String,
      let key = (info["SUPublicEDKey"] as? String).flatMap({ Data(base64Encoded: $0) })
          .flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) })
else {
    print("REFUSED: \(arguments[1]) names no version, build, minimum macOS, or public key")
    exit(1)
}
guard let feed = try? Data(contentsOf: URL(filePath: arguments[0])), let disk = try? Data(contentsOf: image) else {
    print("REFUSED: \(arguments[0]) or \(arguments[2]) can't be read")
    exit(1)
}

func verifies(_ signature: String?, _ data: Data) -> Bool {
    signature.flatMap { Data(base64Encoded: $0) }.map { key.isValidSignature($0, for: data) } ?? false
}

var refusals: [String] = []

// Sparkle checks the signature over every byte before the feed's signature block (SPUExtractSignedFeed.m).
if let block = feed.range(of: Data("<!-- sparkle-signatures:\n".utf8), options: .backwards) {
    let signed = feed[..<block.lowerBound]
    var fields: [String: String] = [:]
    for line in String(decoding: feed[block.upperBound...], as: UTF8.self).split(separator: "\n") {
        let parts = line.split(separator: ":", maxSplits: 1)
        if parts.count == 2 { fields[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces) }
    }
    if fields["length"] != String(signed.count) { refusals.append("its signature doesn't cover the whole feed") }
    if !verifies(fields["edSignature"], Data(signed)) {
        refusals.append("its signature doesn't verify with the public key in Peel")
    }
} else {
    refusals.append("it isn't signed, and Peel takes only a signed feed")
}

/// The elements directly inside each item, with their text and attributes, named as the feed writes them
/// (`sparkle:version`). An enclosure inside `sparkle:deltas` is a delta's, not the update's.
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

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

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

let items = Items()
let parser = XMLParser(data: feed)
parser.delegate = items
if !parser.parse() { refusals.append("it isn't valid XML") }
if items.all.count != 1 { refusals.append("it offers \(items.all.count) updates rather than this one") }
if let item = items.all.first {
    func text(_ name: String) -> String { item[name]?.text ?? "nothing" }
    if text("sparkle:version") != build { refusals.append("its build is \(text("sparkle:version")), not \(build)") }
    if text("sparkle:shortVersionString") != version {
        refusals.append("its version is \(text("sparkle:shortVersionString")), not \(version)")
    }
    if text("sparkle:minimumSystemVersion") != minimum {
        refusals.append("it asks for macOS \(text("sparkle:minimumSystemVersion")), while Peel runs on \(minimum)")
    }
    // Critical from any version, so Sparkle's window offers neither Skip This Version nor Remind Me Later.
    if item["sparkle:criticalUpdate"].map({ $0.attributes["sparkle:version"] != nil }) ?? true {
        refusals.append("it isn't critical from every version")
    }
    // Sparkle offers an update with a hardware requirement to no Mac that lacks it.
    if let requirement = item["sparkle:hardwareRequirements"] {
        refusals.append("it is offered only to Macs with \(requirement.text)")
    }
    let enclosure = item["enclosure"]?.attributes ?? [:]
    if enclosure["url"] != download {
        refusals.append("it downloads \(enclosure["url"] ?? "nothing"), not \(download)")
    }
    if enclosure["length"] != String(disk.count) { refusals.append("its length isn't the disk image's") }
    if !verifies(enclosure["sparkle:edSignature"], disk) {
        refusals.append("the disk image's signature doesn't verify with the public key in Peel")
    }
    if item["description"]?.attributes["sparkle:format"] != "markdown" || text("description").isEmpty {
        refusals.append("it carries no release notes in Markdown")
    }
}

if refusals.isEmpty {
    print("The feed offers Peel \(version) (\(build)) to every Mac on macOS \(minimum) or later, critical,")
    print("from \(download), with its release notes, signed with the key in Peel.")
} else {
    for refusal in refusals { print("REFUSED: the feed: \(refusal).") }
    exit(1)
}
