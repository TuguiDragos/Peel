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
    /// Why nothing in this area is recommended, whatever each item holds.
    public var heldBack: HoldBack?
    /// True when what macOS keeps in its folders for its own services is neither measured nor offered: there they run
    /// as other accounts, whose open files Peel cannot see, or keep caches not even Full Disk Access can read.
    public var leavesMacOSsOwn = false
    /// The folders of `urls` where macOS files reports into folders of its own, so only their files are offered.
    public var onlyFilesIn: [URL] = []
    /// The commands that free an area Peel leaves alone, as its tool's documentation gives them. Peel shows them to
    /// copy and never runs them: they delete for good.
    public var commands: [String] = []

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
    struct Command: Sendable, ExpressibleByStringLiteral {
        enum Need: Sendable {
            case simctl
            case simctlRuntimeOption(String)
        }

        let line: String
        var need: Need?

        init(stringLiteral line: String) {
            self.line = line
        }

        init(_ line: String, needs need: Need) {
            self.line = line
            self.need = need
        }

        func isKnown(simctlRuntimeHelp help: String?) -> Bool {
            switch need {
            case nil: true
            case .simctl: help != nil
            case .simctlRuntimeOption(let option):
                help?.split { !($0.isLetter || $0.isNumber || $0 == "-") }.contains { $0 == option } ?? false
            }
        }
    }

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
        /// True for the folder macOS gives the account for caches (`confstr`'s `_CS_DARWIN_USER_CACHE_DIR`), which
        /// is never in `paths` since macOS chooses where it is.
        var isTheUserCacheFolder = false
        var heldBack: HoldBack?
        var leavesMacOSsOwn = false
        var onlyFilesIn: [String] = []
        var commands: [Command] = []

        /// Each of `paths` on this Mac: one that starts with `/` is under `root`, the rest are in `home`.
        func urls(home: URL, root: URL, userCache: URL?) -> [URL] {
            paths.map { path in
                path.hasPrefix("/")
                    ? root.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                    : home.appending(path: path, directoryHint: .isDirectory)
            } + (isTheUserCacheFolder ? [userCache].compactMap(\.self) : [])
        }

        /// True when the area's size is what it offers, child by child, rather than its places measured whole: one
        /// place may sit inside another of its own, which would count twice.
        var measuresWhatItOffers: Bool { leavesMacOSsOwn || !onlyFilesIn.isEmpty }

        func onlyFilesIn(home: URL, root: URL) -> [URL] {
            onlyFilesIn.map { path in
                path.hasPrefix("/")
                    ? root.appending(path: String(path.dropFirst()), directoryHint: .isDirectory)
                    : home.appending(path: path, directoryHint: .isDirectory)
            }
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
            handling: .readOnly,
            commands: [
                Command("xcrun simctl runtime delete --outdated", needs: .simctlRuntimeOption("--outdated")),
                Command("xcrun simctl delete unavailable", needs: .simctl),
            ]
        ),
        Definition(
            id: "android-sdk",
            category: .development,
            paths: ["Library/Android/sdk/system-images", ".android/avd"],
            handling: .readOnly
        ),
        // rustup's RUSTUP_HOME is `~/.rustup` and keeps each toolchain in `toolchains` (rustup's `config.rs`).
        Definition(
            id: "rust-toolchains",
            category: .development,
            paths: [".rustup/toolchains"],
            handling: .readOnly,
            commands: ["rustup toolchain list", "rustup toolchain uninstall <name>"]
        ),
        // Android's "Install and configure the NDK": every version in the SDK's `ndk` folder; `sdkmanager` removes one.
        Definition(
            id: "android-ndk",
            category: .development,
            paths: ["Library/Android/sdk/ndk"],
            handling: .readOnly,
            commands: [#"~/Library/Android/sdk/cmdline-tools/latest/bin/sdkmanager --uninstall "ndk;<version>""#]
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
            handling: .readOnly,
            commands: ["docker system prune"]
        ),
        Definition(
            id: "orbstack",
            category: .virtualMachines,
            paths: ["Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"],
            handling: .readOnly,
            commands: ["orb delete <name>", "docker image prune -a"]
        ),
        Definition(
            id: "colima",
            category: .virtualMachines,
            paths: [".colima"],
            handling: .readOnly,
            // Without --data, colima delete keeps the images and volumes on the disk.
            commands: ["colima delete --data"]
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
            handling: .readOnly,
            commands: ["podman machine rm <name>"]
        ),
        Definition(
            id: "lima",
            category: .virtualMachines,
            paths: [".lima"],
            handling: .readOnly,
            commands: ["limactl delete <name>"]
        ),
        Definition(
            id: "minikube",
            category: .virtualMachines,
            paths: [".minikube/machines", ".minikube/cache/images"],
            handling: .readOnly,
            commands: ["minikube delete --all --purge"]
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
            handling: .readOnly,
            commands: ["vagrant box remove <name>", "vagrant box prune"]
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
        // macOS's analytics helper can't make the account's crash reports folder again once it is gone, so only the
        // reports in it are offered.
        Definition(
            id: "logs",
            category: .library,
            paths: ["Library/Logs", "Library/Logs/DiagnosticReports"],
            handling: .trash,
            containerFolders: ["Data/Library/Logs"],
            onlyFilesIn: ["Library/Logs/DiagnosticReports"]
        ),
        Definition(
            id: "caches",
            category: .library,
            paths: ["Library/Caches"],
            handling: .trash
        ),
        // macOS empties this folder only in a safe boot (`man confstr`). Apps' helpers keep caches in it, and so do
        // macOS's own services, some of them where not even Full Disk Access reaches.
        Definition(
            id: "user-caches",
            category: .library,
            paths: [],
            handling: .trash,
            isTheUserCacheFolder: true,
            leavesMacOSsOwn: true
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

    /// The total size of `urls` less what is excluded inside them, or nil when any of it could not be measured. A
    /// folder a file provider owns can stall a directory read for minutes, and a very big folder can run out of
    /// time as well. An area with an unknown size is still listed, since it may be the biggest one on the disk.
    private static func size(
        of urls: [URL],
        leaving exclusions: Exclusions,
        measure: @escaping FileSize.Measure
    ) async -> Int64? {
        var total: Int64 = 0
        for url in urls {
            guard var measured = await measure(url) else { return nil }
            for place in exclusions.places(inside: url) where !place.isMissing {
                guard let excluded = await measure(place) else { return nil }
                measured -= excluded
            }
            total += max(0, measured)
        }
        return total
    }

    /// The folders Space empties. Each stays itself, since Space moves what is inside, never the folder.
    static func emptiedFolders(in environment: SearchEnvironment) -> [URL] {
        definitions.filter { $0.handling == .trash }.flatMap {
            $0.urls(
                home: environment.homeDirectory, root: environment.rootDirectory,
                userCache: environment.userCacheDirectory
            )
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

    /// What an area can offer in its `folders`: every child that is not one of the folders themselves, only the files
    /// where macOS files its reports into folders, and nothing named for macOS in an area that leaves macOS's own out.
    private static func offered(in folders: [URL], of definition: Definition, home: URL, root: URL) -> [URL] {
        let paths = Set(folders.map(PathPattern.comparablePath))
        let filesOnly = Set(definition.onlyFilesIn(home: home, root: root).map(PathPattern.comparablePath))
        return folders.flatMap { folder -> [URL] in
            // A folder that can't be listed is measured whole, so its size reads as unknown, never as nothing.
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            else { return [folder] }
            let kept = definition.leavesMacOSsOwn ? names.filter { !isMacOSsOwn($0) } : names
            return kept.map { folder.appending(path: $0) }.filter { child in
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

    /// What is excluded is left out: an area that is excluded is not listed, and what is excluded inside one is
    /// not counted in its size.
    @concurrent
    public static func scan(
        in environment: SearchEnvironment = .current,
        minimumSize: Int64 = SpaceInventory.minimumSize,
        exclusions: Exclusions = .none
    ) async -> SpaceReport {
        await scan(
            home: environment.homeDirectory,
            root: environment.rootDirectory,
            userCache: environment.userCacheDirectory,
            minimumSize: minimumSize,
            exclusions: exclusions,
            measure: FileSize.measure
        )
    }

    /// `root` is where the paths outside the home folder start, so a test can point it at a folder of its own.
    @concurrent
    static func scan(
        home: URL,
        root: URL = URL(filePath: "/", directoryHint: .isDirectory),
        userCache: URL? = nil,
        minimumSize: Int64,
        exclusions: Exclusions = .none,
        measure: @escaping FileSize.Measure,
        simctlRuntimeHelp: @escaping @Sendable () async -> String? = Simctl.runtimeHelp
    ) async -> SpaceReport {
        let containers = appContainers(in: home)
        let groups = groupContainers(in: home)
        let wanted = definitions.compactMap { definition -> (Definition, [URL])? in
            let urls = definition.urls(home: home, root: root, userCache: userCache)
                .filter { FileManager.default.fileExists(atPath: PathPattern.comparablePath(of: $0)) }
                + definition.containerFolders.flatMap { folder in
                    containers.map { $0.appending(path: folder, directoryHint: .isDirectory) }.filter(\.isRealFolder)
                }
                + (definition.groupContainerFolder.map { folder in
                    groups.map { $0.appending(path: folder, directoryHint: .isDirectory) }.filter(\.isRealFolder)
                } ?? [])
            let kept = urls.filter { !exclusions.excludes($0) }
            return kept.isEmpty ? nil : (definition, kept)
        }
        let asksSimctl = wanted.contains { definition, _ in definition.commands.contains { $0.need != nil } }
        async let simctlHelp = asksSimctl ? simctlRuntimeHelp() : nil

        // Four areas are measured at a time. One after another, the wait would be the sum of them all, and a
        // folder that never answers would delay every area after it by its whole budget. Four leaves room for
        // the rest of the app.
        var measured: [(definition: Definition, urls: [URL], size: Int64?)] = []
        await withTaskGroup(of: (Definition, [URL], Int64?).self) { group in
            var pending = wanted.makeIterator()
            func addNext() -> Bool {
                guard !Task.isCancelled, let (definition, urls) = pending.next() else { return false }
                let measured = definition.measuresWhatItOffers
                    ? offered(in: urls, of: definition, home: home, root: root).filter { !exclusions.excludes($0) }
                    : urls
                group.addTask { (definition, urls, await size(of: measured, leaving: exclusions, measure: measure)) }
                return true
            }
            for _ in 0..<4 where addNext() {}
            while let area = await group.next() {
                _ = addNext()
                measured.append(area)
            }
        }
        let help = await simctlHelp
        let items = measured.filter { $0.size.map { $0 >= minimumSize } ?? true }.map { definition, urls, size in
            SpaceItem(
                id: definition.id,
                category: definition.category,
                urls: urls,
                size: size,
                handling: definition.handling,
                heldBack: definition.heldBack,
                leavesMacOSsOwn: definition.leavesMacOSsOwn,
                onlyFilesIn: definition.onlyFilesIn(home: home, root: root),
                commands: definition.commands.filter { $0.isKnown(simctlRuntimeHelp: help) }.map(\.line)
            )
        }

        return SpaceReport(
            // An unknown size sorts first: an area that ran out of time is most likely one of the biggest.
            items: items.sorted { ($0.size ?? .max) > ($1.size ?? .max) },
            storage: DeviceInfo.storage(of: home),
            purgeable: purgeableSpace(of: home),
            snapshots: await LocalSnapshots.list(),
            needsFullDiskAccess: items.contains {
                $0.size == nil && $0.urls.contains { FullDiskAccess.canList($0) == .missing }
            }
        )
    }

    static func purgeableSpace(of url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ])
        guard let important = values?.volumeAvailableCapacityForImportantUsage,
              let free = values?.volumeAvailableCapacity else { return nil }
        return max(0, important - Int64(free))
    }
}
