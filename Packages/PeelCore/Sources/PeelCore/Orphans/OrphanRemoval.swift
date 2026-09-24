import Foundation

public enum OrphanRemoval {
    /// Moves `items` to the Trash, but only those that are still orphaned when checked again. An app installed
    /// since the scan may own some of them, so those stay in place and fail with `claimedSinceScan`.
    @concurrent
    public static func trash(
        _ items: [OrphanItem],
        installedApps: [InstalledApp],
        scanner: OrphanScanner,
        using trashService: TrashService
    ) async -> TrashResult {
        let orphaned = await scanner.stillOrphaned(items, installedApps: installedApps)
        let kept = Set(orphaned.map(\.url))
        let privileged = Set(orphaned.filter(\.requiresPrivileges).map(\.url))
        var result = await trashService.trash(orphaned.map(\.url), usingHelperFor: privileged)
        result.failures += items.filter { !kept.contains($0.url) }.map { TrashFailure(url: $0.url, reason: .claimedSinceScan) }
        return result
    }
}
