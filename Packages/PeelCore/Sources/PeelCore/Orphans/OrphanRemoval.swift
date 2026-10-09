import Foundation

public enum OrphanRemoval {
    /// Moves `items` to the Trash, but only those that are still orphaned when checked again. An app installed
    /// since the scan may own some of them, so those stay in place and fail with `claimedSinceScan`. Without
    /// `mayUseHelper`, as for `peel`, what needs an administrator is not tried and fails with `needsHelper`.
    @concurrent
    public static func trash(
        _ items: [OrphanItem],
        installedApps: [InstalledApp],
        remembered: [RememberedApp],
        scanner: OrphanScanner,
        using trashService: TrashService,
        mayUseHelper: Bool
    ) async -> TrashResult {
        let orphaned = await scanner.stillOrphaned(items, installedApps: installedApps, remembered: remembered)
        let kept = Set(orphaned.map(\.url))
        let privileged = Set(orphaned.filter(\.requiresPrivileges).map(\.url))
        let moving = mayUseHelper ? orphaned.map(\.url) : orphaned.map(\.url).filter { !privileged.contains($0) }
        var result = await trashService.trash(moving, usingHelperFor: mayUseHelper ? privileged : [])
        if !mayUseHelper {
            result.failures += orphaned.filter(\.requiresPrivileges).map {
                TrashFailure(url: $0.url, reason: .needsHelper)
            }
        }
        result.failures += items.filter { !kept.contains($0.url) }.map {
            TrashFailure(url: $0.url, reason: .claimedSinceScan)
        }
        return result
    }
}
