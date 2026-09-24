public import Foundation

/// An area of the disk that can take up a lot of room, such as simulators or virtual machines. Most areas are
/// read-only here: their own app or tool is the right place to remove them. Peel never adds them up into a
/// "junk" total.
public struct SpaceItem: Sendable, Hashable, Identifiable {
    public enum Handling: Sendable, Hashable {
        /// Only the app or tool that owns it should remove it. The app's words for the area say how.
        case readOnly
        /// Peel can move the files and folders inside it to the Trash (see `SpaceRemoval`).
        case trash
    }

    public enum Category: String, Sendable, Hashable, CaseIterable {
        case development
        case virtualMachines
        case media
        case cloud
        case library
    }

    public let id: String
    public let category: Category
    public let urls: [URL]
    /// Nil when measuring one of its folders ran out of time or was refused. Unknown is not the same as empty.
    public let size: Int64?
    public let handling: Handling

    public var isReadOnly: Bool {
        if case .readOnly = handling { true } else { false }
    }
}

public struct SpaceReport: Sendable {
    public let items: [SpaceItem]
    public let storage: DeviceInfo.Storage
    /// Space macOS can reclaim by itself, mostly local snapshots and caches.
    public let purgeable: Int64
    /// Local snapshots: copies of the disk kept on the disk itself. Peel explains them but never removes one,
    /// because deleting a snapshot cannot be undone.
    public let snapshots: [LocalSnapshot]
    /// True when an area went unmeasured because macOS refused access, which Full Disk Access would grant.
    public let needsFullDiskAccess: Bool

    public func items(in category: SpaceItem.Category) -> [SpaceItem] {
        items.filter { $0.category == category }
    }
}

public enum SpaceInventory {
    struct Definition: Sendable {
        let id: String
        let category: SpaceItem.Category
        let paths: [String]
        let handling: SpaceItem.Handling
    }

    /// The identifier of every area. Public so the app can check that it has words for each one: the words
    /// live in the app, because this package has no string catalog.
    public static var definitionIdentifiers: [String] { definitions.map(\.id) }

    static let definitions: [Definition] = [
        Definition(
            id: "simulators",
            category: .development,
            paths: ["Library/Developer/CoreSimulator/Devices", "/Library/Developer/CoreSimulator/Images"],
            handling: .readOnly
        ),
        Definition(
            id: "android-sdk",
            category: .development,
            paths: ["Library/Android/sdk/system-images", ".android/avd"],
            handling: .readOnly
        ),
        Definition(
            id: "unity-assets",
            category: .development,
            paths: ["Library/Unity/Asset Store-5.x"],
            handling: .readOnly
        ),
        Definition(
            id: "docker",
            category: .virtualMachines,
            paths: ["Library/Containers/com.docker.docker/Data/vms"],
            handling: .readOnly
        ),
        Definition(
            id: "orbstack",
            category: .virtualMachines,
            paths: ["Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"],
            handling: .readOnly
        ),
        Definition(
            id: "colima",
            category: .virtualMachines,
            paths: [".colima"],
            handling: .readOnly
        ),
        Definition(
            id: "utm",
            category: .virtualMachines,
            paths: ["Library/Containers/com.utmapp.UTM/Data/Documents"],
            handling: .readOnly
        ),
        Definition(
            id: "parallels",
            category: .virtualMachines,
            paths: ["Parallels"],
            handling: .readOnly
        ),
        Definition(
            id: "vmware",
            category: .virtualMachines,
            paths: ["Virtual Machines.localized"],
            handling: .readOnly
        ),
        Definition(
            id: "podman",
            category: .virtualMachines,
            paths: [".local/share/containers/podman/machine"],
            handling: .readOnly
        ),
        Definition(
            id: "lima",
            category: .virtualMachines,
            paths: [".lima"],
            handling: .readOnly
        ),
        Definition(
            id: "minikube",
            category: .virtualMachines,
            paths: [".minikube/machines", ".minikube/cache"],
            handling: .readOnly
        ),
        Definition(
            id: "virtualbox",
            category: .virtualMachines,
            paths: ["VirtualBox VMs"],
            handling: .readOnly
        ),
        Definition(
            id: "vagrant",
            category: .virtualMachines,
            paths: [".vagrant.d/boxes"],
            handling: .readOnly
        ),
        Definition(
            id: "podcasts",
            category: .media,
            paths: ["Library/Group Containers/243LU875E5.groups.com.apple.podcasts"],
            handling: .readOnly
        ),
        Definition(
            id: "tv",
            category: .media,
            paths: ["Movies/TV"],
            handling: .readOnly
        ),
        Definition(
            id: "messages",
            category: .media,
            paths: ["Library/Messages/Attachments"],
            handling: .readOnly
        ),
        Definition(
            id: "wallpapers",
            category: .media,
            paths: [
                "Library/Application Support/com.apple.wallpaper/aerials/videos",
                "/Library/Application Support/com.apple.idleassetsd/Customer",
            ],
            handling: .readOnly
        ),
        Definition(
            id: "cloudstorage",
            category: .cloud,
            paths: ["Library/CloudStorage"],
            handling: .readOnly
        ),
        Definition(
            id: "icloud",
            category: .cloud,
            paths: ["Library/Mobile Documents/com~apple~CloudDocs"],
            handling: .readOnly
        ),
        Definition(
            id: "logs",
            category: .library,
            paths: ["Library/Logs"],
            handling: .trash
        ),
        Definition(
            id: "caches",
            category: .library,
            paths: ["Library/Caches"],
            handling: .trash
        ),
    ]

    /// The total size of `urls`, or nil when any of them could not be measured. A folder a file provider owns
    /// can stall a directory read for minutes, and a very big folder can run out of time as well. An area with
    /// an unknown size is still listed, since it may be the biggest one on the disk.
    private static func size(of urls: [URL], measure: @escaping FileSize.Measure) async -> Int64? {
        var total: Int64 = 0
        for url in urls {
            guard let measured = await measure(url) else { return nil }
            total += measured
        }
        return total
    }

    /// Anything smaller than this is noise in a report about space.
    public static let minimumSize: Int64 = 50 * 1_000_000

    @concurrent
    public static func scan(home: URL = .homeDirectory, minimumSize: Int64 = SpaceInventory.minimumSize) async -> SpaceReport {
        await scan(home: home, root: URL(filePath: "/", directoryHint: .isDirectory), minimumSize: minimumSize, measure: FileSize.measure)
    }

    /// `root` is where the paths outside the home folder start, so a test can point it at a folder of its own.
    @concurrent
    static func scan(
        home: URL,
        root: URL = URL(filePath: "/", directoryHint: .isDirectory),
        minimumSize: Int64,
        measure: @escaping FileSize.Measure
    ) async -> SpaceReport {
        let wanted = definitions.compactMap { definition -> (Definition, [URL])? in
            let urls = definition.paths
                .map { path in
                    path.hasPrefix("/")
                        ? root.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                        : home.appending(path: path, directoryHint: .isDirectory)
                }
                .filter { FileManager.default.fileExists(atPath: PathPattern.comparablePath(of: $0)) }
            return urls.isEmpty ? nil : (definition, urls)
        }

        // Four areas are measured at a time. One after another, the wait would be the sum of them all, and a
        // folder that never answers would delay every area after it by its whole budget. Four leaves room for
        // the rest of the app.
        var items: [SpaceItem] = []
        await withTaskGroup(of: (Definition, [URL], Int64?).self) { group in
            var pending = wanted.makeIterator()
            func addNext() -> Bool {
                guard !Task.isCancelled, let (definition, urls) = pending.next() else { return false }
                group.addTask { (definition, urls, await size(of: urls, measure: measure)) }
                return true
            }
            for _ in 0..<4 where addNext() {}
            while let (definition, urls, size) = await group.next() {
                _ = addNext()
                guard size.map({ $0 >= minimumSize }) ?? true else { continue }
                items.append(SpaceItem(
                    id: definition.id,
                    category: definition.category,
                    urls: urls,
                    size: size,
                    handling: definition.handling
                ))
            }
        }

        return SpaceReport(
            // An unknown size sorts first: an area that ran out of time is most likely one of the biggest.
            items: items.sorted { ($0.size ?? .max) > ($1.size ?? .max) },
            storage: DeviceInfo.storage(of: home),
            purgeable: purgeableSpace(of: home),
            snapshots: await LocalSnapshots.list(),
            needsFullDiskAccess: items.contains { $0.size == nil && $0.urls.contains { FullDiskAccess.canList($0) == .missing } }
        )
    }

    static func purgeableSpace(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let important = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let free = Int64(values?.volumeAvailableCapacity ?? 0)
        return max(0, important - free)
    }
}
