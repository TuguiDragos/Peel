public import Foundation
internal import PeelPrivileged

/// Homebrew's record of an installed cask: its folder in the Caskroom, which keeps Homebrew counting the cask as
/// installed, and the links in the command and shell completion folders that lead into it or into the cask's apps.
public enum HomebrewReceipt {
    /// What goes to the Trash when Peel forgets `cask`, its Caskroom folder first. Nothing while any of its apps is
    /// still there, since Homebrew then still manages an app on this Mac.
    public static func items(of cask: HomebrewPackage, environment: SearchEnvironment = .current) -> [URL] {
        guard cask.checkingItsApps().isMissingItsApps, let folder = cask.caskroomFolder,
              FileAccess.isARealFolder(folder)
        else { return [] }
        let destinations = [PathPattern.comparablePath(of: folder)] + cask.appTargets
        var links: [URL] = []
        for location in environment.locations where location.kind.isForLinks {
            for destination in destinations {
                links += Self.links(in: location.url, leadingInto: destination).filter { !links.contains($0) }
            }
        }
        return [folder] + links
    }

    /// Moves the record of each cask whose apps are gone to the Trash, so Homebrew stops listing it and History can
    /// put it back. `brew uninstall` would delete the same folder for good.
    @concurrent
    public static func forget(_ casks: [HomebrewPackage], exclusions: Exclusions) async -> TrashResult {
        await forget(casks, through: TrashService(exclusions: exclusions), environment: .current)
    }

    static func forget(
        _ casks: [HomebrewPackage],
        through service: TrashService,
        environment: SearchEnvironment
    ) async -> TrashResult {
        let items = casks.flatMap { items(of: $0, environment: environment) }
        guard !items.isEmpty else { return TrashResult() }
        return await service.trash(items, usingHelperFor: Set(items.filter(FileAccess.requiresPrivilegesToRemove)))
    }

    /// The links directly in `folder` that lead to `destination` or inside it, read without following them.
    static func links(in folder: URL, leadingInto destination: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.sorted().map { folder.appending(path: $0) }.filter { link in
            let path = link.path(percentEncoded: false)
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return false }
            let resolved = URL(filePath: target, relativeTo: folder).standardizedFileURL
            return PathComponents.isPath(PathPattern.comparablePath(of: resolved), inside: destination)
        }
    }
}
