import Foundation

/// The identifier an item declares about itself, for when its file name matches nothing: a plug-in is named for
/// what it does rather than for who made it, a crash report for the process and the time, and a container is
/// sometimes named by a UUID. The identifier is only a claim, so it goes through the same matching as a file name.
enum DeclaredIdentifier {
    static func of(_ url: URL, kind: SearchLocation.Kind) -> String? {
        switch kind {
        case .plugIns: Plugins.declaredIdentifier(at: url)
        case .frameworks: framework(at: url)
        case .containers: container(at: url)
        case .logs: CrashReport.bundleIdentifier(of: url)
        default: nil
        }
    }

    /// True for code macOS loads, named for what it does, so what it declares is read even when the name matches.
    static func outranksTheName(of url: URL, kind: SearchLocation.Kind) -> Bool {
        kind.isLoadedCode
    }

    /// True for a diagnostic report, whose name is the process's and the time's and never says whose it is: only
    /// what it declares can claim it, and a `.diag` declares nothing.
    static func nameSaysNothing(of url: URL, kind: SearchLocation.Kind) -> Bool {
        kind == .logs && CrashReport.isInADiagnosticReportsFolder(url)
    }

    /// The `CFBundleIdentifier` a framework's `Resources/Info.plist` declares.
    private static func framework(at url: URL) -> String? {
        let resources = url.appending(path: "Resources", directoryHint: .isDirectory)
        return AppInspector.infoDictionary(in: resources)?["CFBundleIdentifier"] as? String
    }

    /// The `MCMMetadataIdentifier` in a container's metadata, read only when the folder's name is not already an
    /// identifier. On macOS 26, a container whose name is an identifier is named after that value, so reading
    /// the file would add nothing.
    private static func container(at url: URL) -> String? {
        guard !Identifier.isReverseDNS(url.lastPathComponent) else { return nil }
        let metadata = url.appending(path: ".com.apple.containermanagerd.metadata.plist")
        return BoundedRead.propertyList(at: metadata)?["MCMMetadataIdentifier"] as? String
    }
}
