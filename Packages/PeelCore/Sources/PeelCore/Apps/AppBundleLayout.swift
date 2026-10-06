import Foundation
internal import PeelPrivileged

/// Where an app bundle keeps the Info.plist and the executable that describe the app. A Mac app keeps them in
/// `Contents`. An iPhone or iPad app installed on a Mac is a wrapper: its own bundle sits in `Wrapper`, where the
/// wrapper's `WrappedBundle` link leads, with both at its top and signed on its own.
struct AppBundleLayout {
    let infoFolder: URL
    let executableFolder: URL
    let signedBundle: URL
    let isWrapped: Bool

    init(of bundle: URL) {
        if let wrapped = Self.wrappedBundle(in: bundle) {
            (infoFolder, executableFolder, signedBundle, isWrapped) = (wrapped, wrapped, wrapped, true)
        } else {
            let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
            infoFolder = contents
            executableFolder = contents.appending(path: "MacOS", directoryHint: .isDirectory)
            (signedBundle, isWrapped) = (bundle, false)
        }
    }

    /// The bundle `WrappedBundle` leads to, only when it names a bundle directly in `Wrapper`, so that a link
    /// leading anywhere else names nothing.
    static func wrappedBundle(in bundle: URL) -> URL? {
        let link = bundle.appending(path: "WrappedBundle").path(percentEncoded: false)
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link) else { return nil }
        let names = PathComponents.of(destination)
        guard names.count == 2, names[0] == "Wrapper", names[1].hasSuffix(".app"), names[1] != ".app" else {
            return nil
        }
        return bundle.appending(path: "Wrapper", directoryHint: .isDirectory)
            .appending(path: names[1], directoryHint: .isDirectory)
    }
}
