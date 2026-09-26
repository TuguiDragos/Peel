public import Foundation
internal import PeelPrivileged

public struct DeviceInfo: Sendable, Hashable {
    public struct Storage: Sendable, Hashable {
        public let total: Int64
        public let free: Int64

        public init(total: Int64, free: Int64) {
            self.total = max(0, total)
            self.free = min(max(0, free), self.total)
        }

        public var used: Int64 { total - free }
        public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    }

    /// The About pane of System Settings (General > About), which System Profiler provides as an extension.
    public static let aboutURL = URL(string: "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension")!

    public let model: String
    public let modelIdentifier: String
    public let chip: String
    public let systemVersion: String
    public let memory: Int64
    public let storage: Storage

    public init(model: String, modelIdentifier: String, chip: String, systemVersion: String, memory: Int64, storage: Storage) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.systemVersion = systemVersion
        self.memory = memory
        self.storage = storage
    }

    /// Returns a copy with the disk's total and free space read again. The other details don't change while
    /// Peel is open, and the marketing name is slow to read.
    public func withStorageRead(of home: URL = .homeDirectory) -> DeviceInfo {
        DeviceInfo(
            model: model,
            modelIdentifier: modelIdentifier,
            chip: chip,
            systemVersion: systemVersion,
            memory: memory,
            storage: Self.storage(of: home)
        )
    }

    /// Reads everything but the marketing name, which needs a `system_profiler` process. The model identifier
    /// stands in for the name, so Home can show the Mac at once and fill in the name when it arrives.
    @concurrent
    public static func withoutTheModelName(home: URL = .homeDirectory) async -> DeviceInfo {
        let identifier = sysctl("hw.model") ?? ""
        return DeviceInfo(
            model: identifier,
            modelIdentifier: identifier,
            chip: sysctl("machdep.cpu.brand_string") ?? "",
            systemVersion: versionString(ProcessInfo.processInfo.operatingSystemVersion),
            memory: Int64(ProcessInfo.processInfo.physicalMemory),
            storage: storage(of: home)
        )
    }

    /// Returns a copy with `name` in place of the model identifier. A nil or empty name changes nothing.
    public func named(_ name: String?) -> DeviceInfo {
        guard let name, !name.isEmpty else { return self }
        return DeviceInfo(
            model: name,
            modelIdentifier: modelIdentifier,
            chip: chip,
            systemVersion: systemVersion,
            memory: memory,
            storage: storage
        )
    }

    @concurrent
    public static func current(home: URL = .homeDirectory) async -> DeviceInfo {
        let identifier = sysctl("hw.model") ?? ""
        return DeviceInfo(
            model: await marketingName() ?? identifier,
            modelIdentifier: identifier,
            chip: sysctl("machdep.cpu.brand_string") ?? "",
            systemVersion: versionString(ProcessInfo.processInfo.operatingSystemVersion),
            memory: Int64(ProcessInfo.processInfo.physicalMemory),
            storage: storage(of: home)
        )
    }

    static func versionString(_ version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion > 0 ? base + ".\(version.patchVersion)" : base
    }

    public static func storage(of url: URL) -> Storage {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return storage(
            total: values?.volumeTotalCapacity,
            available: values?.volumeAvailableCapacity,
            important: values?.volumeAvailableCapacityForImportantUsage
        )
    }

    /// What is free is the room macOS would make for an important file, which counts what it can purge. A volume
    /// that does not report that answers zero, and its plain free space is then what is free.
    static func storage(total: Int?, available: Int?, important: Int64?) -> Storage {
        let important = important ?? 0
        return Storage(total: Int64(total ?? 0), free: important > 0 ? important : Int64(available ?? 0))
    }

    static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? nil : value
    }

    /// The name people know, like "MacBook Air". Only `system_profiler` reports it on Apple silicon.
    public static func marketingName() async -> String? {
        guard
            case .success(let output) = await Subprocess.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], timeout: 5),
            output.status == 0
        else { return nil }
        return marketingName(fromSystemProfiler: output.standardOutput)
    }

    static func marketingName(fromSystemProfiler data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first,
              let name = hardware["machine_name"] as? String, !name.isEmpty
        else { return nil }
        return name
    }
}
