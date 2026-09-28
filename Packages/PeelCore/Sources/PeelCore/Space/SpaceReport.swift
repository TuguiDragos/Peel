public import Foundation
internal import PeelPrivileged

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
    /// Why nothing in this area is selected for the person, whatever each item holds.
    public var heldBack: HoldBack?
    /// True when what macOS keeps in its folders for its own services is neither measured nor offered: they run as
    /// other accounts, whose open files Peel cannot see.
    public var leavesMacOSsOwn = false
    /// The folders of `urls` where macOS files reports into folders of its own, so only their files are offered.
    public var onlyFilesIn: [URL] = []

    public var isReadOnly: Bool {
        if case .readOnly = handling { true } else { false }
    }
}

public struct SpaceReport: Sendable {
    public let items: [SpaceItem]
    public let storage: DeviceInfo.Storage
    /// Space macOS can reclaim by itself, mostly local snapshots and caches. Nil when the volume did not say.
    public let purgeable: Int64?
    /// Local snapshots: copies of the disk kept on the disk itself. Peel explains them but never removes one,
    /// because deleting a snapshot cannot be undone. Nil when `diskutil` did not say.
    public let snapshots: [LocalSnapshot]?
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
        /// The folders inside every app's container (`Library/Containers/<identifier>`) that belong to this area too.
        var containerFolders: [String] = []
        /// The folder inside every group container not Apple's own (`Library/Group Containers/<group>`) that belongs
        /// to this area too.
        var groupContainerFolder: String?
        var heldBack: HoldBack?
        var leavesMacOSsOwn = false
        var onlyFilesIn: [String] = []

        /// Each of `paths` on this Mac: one that starts with `/` is under `root`, the rest are in `home`.
        func urls(home: URL, root: URL) -> [URL] {
            paths.map { path in
                path.hasPrefix("/")
                    ? root.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                    : home.appending(path: path, directoryHint: .isDirectory)
            }
        }

        func onlyFilesIn(root: URL) -> [URL] {
            onlyFilesIn.map { root.appending(path: String($0.dropFirst()), directoryHint: .isDirectory) }
        }
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
            paths: [".minikube/machines", ".minikube/cache/images"],
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
            handling: .trash,
            containerFolders: ["Data/Library/Logs"]
        ),
        Definition(
            id: "caches",
            category: .library,
            paths: ["Library/Caches"],
            handling: .trash
        ),
        Definition(
            id: "container-caches",
            category: .library,
            paths: [],
            handling: .trash,
            containerFolders: ["Data/Library/Caches", "Data/tmp"],
            groupContainerFolder: "Library/Caches"
        ),
        // Sandboxed, Mail writes only the second folder. The first is what an older Mail left in the Library itself.
        Definition(
            id: "mail-downloads",
            category: .library,
            paths: ["Library/Mail Downloads", "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
            handling: .trash,
            heldBack: .openedFromMail
        ),
        // Blizzard's support names this folder as the Battle.net cache, whose removal does not affect game data
        // (us.support.blizzard.com/en/article/34721). It belongs to every account on the Mac.
        Definition(
            id: "battlenet-cache",
            category: .library,
            paths: ["/Users/Shared/Blizzard/Battle.net"],
            handling: .trash,
            heldBack: .sharedWithEveryone
        ),
        Definition(
            id: "system-caches",
            category: .library,
            paths: ["/Library/Caches"],
            handling: .trash,
            leavesMacOSsOwn: true
        ),
        Definition(
            id: "system-logs",
            category: .library,
            paths: ["/Library/Logs", "/Library/Logs/DiagnosticReports"],
            handling: .trash,
            leavesMacOSsOwn: true,
            onlyFilesIn: ["/Library/Logs/DiagnosticReports"]
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

    /// The folders Space empties. Each stays itself, since Space moves what is inside, never the folder.
    static func emptiedFolders(in environment: SearchEnvironment) -> [URL] {
        definitions.filter { $0.handling == .trash }.flatMap {
            $0.urls(home: environment.homeDirectory, root: environment.rootDirectory)
        }
    }

    /// Every app's container, listed rather than matched with `glob`, which stops at 128 paths.
    static func appContainers(in home: URL) -> [URL] {
        folders(in: home.appending(path: "Library/Containers", directoryHint: .isDirectory))
    }

    /// Every group container but Apple's own, which hold what macOS keeps for its apps and are never emptied.
    static func groupContainers(in home: URL) -> [URL] {
        folders(in: home.appending(path: "Library/Group Containers", directoryHint: .isDirectory))
            .filter { !ProtectedData.isApplesName($0.lastPathComponent) }
    }

    /// What an area that leaves macOS's own out can offer in its `folders`: every child not named for macOS and not
    /// one of the folders themselves, and only the files where macOS files its reports into folders.
    private static func offered(in folders: [URL], of definition: Definition, root: URL) -> [URL] {
        let paths = Set(folders.map(PathPattern.comparablePath))
        let filesOnly = Set(definition.onlyFilesIn(root: root).map(PathPattern.comparablePath))
        return folders.flatMap { folder in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return names.filter { !isMacOSsOwn($0) }.map { folder.appending(path: $0) }.filter { child in
                !paths.contains(PathPattern.comparablePath(of: child))
                    && !(filesOnly.contains(PathPattern.comparablePath(of: folder)) && child.isRealFolder)
            }
        }
    }

    /// Whether macOS keeps `name` for its own services in a folder every account shares.
    static func isMacOSsOwn(_ name: String) -> Bool {
        SystemCaches.isMacOSs(name) || SystemLogs.isMacOSs(name)
    }

    private static func folders(in parent: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path(percentEncoded: false))) ?? []
        return names.sorted().map { parent.appending(path: $0, directoryHint: .isDirectory) }.filter(\.isRealFolder)
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
        let containers = appContainers(in: home)
        let groups = groupContainers(in: home)
        let wanted = definitions.compactMap { definition -> (Definition, [URL])? in
            let urls = definition.urls(home: home, root: root)
                .filter { FileManager.default.fileExists(atPath: PathPattern.comparablePath(of: $0)) }
                + definition.containerFolders.flatMap { folder in
                    containers.map { $0.appending(path: folder, directoryHint: .isDirectory) }.filter(\.isRealFolder)
                }
                + (definition.groupContainerFolder.map { folder in
                    groups.map { $0.appending(path: folder, directoryHint: .isDirectory) }.filter(\.isRealFolder)
                } ?? [])
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
                let measured = definition.leavesMacOSsOwn ? offered(in: urls, of: definition, root: root) : urls
                group.addTask { (definition, urls, await size(of: measured, measure: measure)) }
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
                    handling: definition.handling,
                    heldBack: definition.heldBack,
                    leavesMacOSsOwn: definition.leavesMacOSsOwn,
                    onlyFilesIn: definition.onlyFilesIn(root: root)
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

    static func purgeableSpace(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        guard let important = values?.volumeAvailableCapacityForImportantUsage,
              let free = values?.volumeAvailableCapacity else { return nil }
        return max(0, important - Int64(free))
    }
}
