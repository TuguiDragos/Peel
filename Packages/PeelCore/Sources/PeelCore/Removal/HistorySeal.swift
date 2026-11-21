import CryptoKit
public import Foundation
internal import PeelPrivileged
import Security
import Synchronization

/// The seal on what History keeps: an HMAC of what Put Back believes of each record and journal line, made with a key
/// Peel keeps in the Keychain. Any program of the account can write History's files, so a record without the seal a
/// key it can't read makes is no word of Peel's on where to put an item back.
public struct HistorySeal: Sendable {
    private let key: SymmetricKey
    /// True for a key made in this run: a seal no key made can be one an earlier key made, so it is read as no seal.
    private let isNew: Bool

    init(key: SymmetricKey, isNew: Bool = false) {
        self.key = key
        self.isNew = isNew
    }

    /// What a seal says of what it is on.
    public enum Trust: Sendable, Equatable {
        /// Peel wrote it as it reads now.
        case sealed
        /// It carries no seal: an earlier version of Peel wrote it, or the Keychain didn't answer then, or this is
        /// `peel`, which never reads the key.
        case unsealed
        /// Its seal doesn't match what it says, so something other than Peel wrote it or changed it.
        case forged
    }

    /// The seal Peel's app writes and checks with, once the Keychain answered (`answered`); nil for `peel` and for
    /// tests, which then write no seal and check none.
    public static var current: HistorySeal? { standIn ?? reading.seal }

    /// The seal a test writes and checks with.
    @TaskLocal static var standIn: HistorySeal?

    /// The read of the key the app makes, or one a test stands in for a Keychain that doesn't answer.
    @TaskLocal static var reading = keychain

    private static let keychain = Reading()

    /// Lets the app seal History with the key it keeps in the Keychain, made the first time, so nothing asks the
    /// person. The key is read once: at launch (`readTheKey`), or before then by whatever first writes or judges
    /// History. Without an answer from the Keychain, History is written without a seal and read as an earlier
    /// version's. `peel` never asks the Keychain.
    public static func useTheKeychain() {
        keychain.allow { KeychainKey.read().map { HistorySeal(key: $0.key, isNew: $0.isNew) } }
    }

    /// Starts the read of the key, so the Keychain answers beside the rest of the launch.
    public static func readTheKey() {
        keychain.start()
    }

    /// Returns once the key has answered, starting its read if nothing has yet; at once where no read is allowed.
    public static func answered() async {
        guard standIn == nil else { return }
        await reading.answered()
    }

    /// Deletes the key's item, found by its service and account, never by its name, answering whether it is gone. Away
    /// from the main thread, since a locked keychain asks the person first.
    @concurrent public static func forgetTheKeychainKey() async -> Bool {
        // A first read may still be making the key, which would then outlive its deletion.
        await keychain.answered()
        keychain.forget()
        return KeychainKey.delete()
    }

    /// The one read of the key, made once it is allowed, on a thread of its own: the Keychain may wait for the person.
    final class Reading: Sendable {
        private struct State {
            var read: (@Sendable () -> HistorySeal?)?
            var seal: HistorySeal?
            var answer: Task<Void, Never>?
        }

        private let state = Mutex(State())

        var seal: HistorySeal? { state.withLock { $0.seal } }

        func allow(_ read: @escaping @Sendable () -> HistorySeal?) {
            state.withLock { if $0.read == nil { $0.read = read } }
        }

        func start() {
            state.withLock { state in
                guard state.answer == nil, let read = state.read else { return }
                state.answer = Task.detached { [self] in
                    let seal = await withCheckedContinuation { continuation in
                        let thread = Thread { continuation.resume(returning: read()) }
                        thread.qualityOfService = .userInitiated
                        thread.start()
                    }
                    self.state.withLock { $0.seal = seal }
                }
            }
        }

        func answered() async {
            start()
            await state.withLock { $0.answer }?.value
        }

        func forget() {
            state.withLock { $0.seal = nil }
        }
    }

    func seal(_ record: RemovalRecord) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Self.message(of: record), using: key))
    }

    func seal(_ entry: RemovalJournal.Entry) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Self.message(of: entry), using: key))
    }

    func trust(of record: RemovalRecord) -> Trust {
        trust(of: record.seal, on: Self.message(of: record))
    }

    func trust(of entry: RemovalJournal.Entry) -> Trust {
        trust(of: entry.seal, on: Self.message(of: entry))
    }

    private func trust(of seal: Data?, on message: Data) -> Trust {
        guard let seal else { return .unsealed }
        if HMAC<SHA256>.isValidAuthenticationCode(seal, authenticating: message, using: key) { return .sealed }
        return isNew ? .unsealed : .forged
    }

    /// What a seal covers, in one fixed order: what Put Back reads of an item, with the time as History writes it.
    private struct Sealed: Encodable {
        let kind: String
        let id: UUID?
        let batch: UUID
        let originalPath: String
        let trashedPath: String
        let time: String
        let disk: TrashedDisk?
        let identity: TrashedItem.Identity?
        let replacedBy: TrashedItem.Identity?
        let stoppedJob: String?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func message(of record: RemovalRecord) -> Data {
        (try? encoder.encode(Sealed(
            kind: "record", id: record.id, batch: record.batch,
            originalPath: record.originalURL.path(percentEncoded: false),
            trashedPath: record.trashedURL.path(percentEncoded: false), time: LogTime.text(for: record.date),
            disk: record.disk, identity: record.identity, replacedBy: record.replacedBy, stoppedJob: record.stoppedJob
        ))) ?? Data()
    }

    private static func message(of entry: RemovalJournal.Entry) -> Data {
        let item = entry.item
        return (try? encoder.encode(Sealed(
            kind: "line", id: nil, batch: entry.batch,
            originalPath: item.originalURL.path(percentEncoded: false),
            trashedPath: item.trashedURL.path(percentEncoded: false), time: LogTime.text(for: item.date),
            disk: entry.disk, identity: item.identity, replacedBy: item.replacedBy, stoppedJob: item.stoppedJob
        ))) ?? Data()
    }
}

/// The key of History's seal, a generic password in the Keychain that only the app that made it reads without
/// macOS asking the person.
enum KeychainKey {
    /// The item, by its class, service, and account alone, so an item another program named alike is never it.
    static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tuguidragos.Peel.History",
            kSecAttrAccount as String: "seal",
        ]
    }

    static func read() -> (key: SymmetricKey, isNew: Bool)? {
        var found: CFTypeRef?
        var asked = query
        asked[kSecReturnData as String] = true
        switch SecItemCopyMatching(asked as CFDictionary, &found) {
        case errSecSuccess:
            guard let data = found as? Data, data.count == 32 else { return nil }
            return (SymmetricKey(data: data), false)
        case errSecItemNotFound:
            return make().map { ($0, true) }
        default:
            return nil
        }
    }

    static func delete() -> Bool {
        [errSecSuccess, errSecItemNotFound].contains(SecItemDelete(query as CFDictionary))
    }

    private static func make() -> SymmetricKey? {
        let key = SymmetricKey(size: .bits256)
        var item = query
        item[kSecAttrLabel as String] = "Peel History"
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}

/// A place macOS keeps from programs that weren't allowed in, which Peel reaches with Full Disk Access: Put Back
/// takes an item there from a record Peel can't check only once the person says so.
public enum GuardedPlace: Sendable, Hashable {
    case desktop, documents, downloads, iCloudDrive
    /// The container of an app, named by its identifier.
    case container(String)
    /// A group container, named by its group.
    case groupContainer(String)

    /// The guarded place `url` is in, if any.
    public init?(of url: URL, home: URL = .homeDirectory) {
        let names = PathComponents.of(PathPattern.comparablePath(of: url).lowercased())
        let homeNames = PathComponents.of(PathPattern.comparablePath(of: home).lowercased())
        let original = PathComponents.of(PathPattern.comparablePath(of: url))
        guard names.count > homeNames.count, names.starts(with: homeNames) else { return nil }
        let inside = Array(names.dropFirst(homeNames.count))
        let spelled = Array(original.dropFirst(homeNames.count))
        switch inside.first {
        case "desktop": self = .desktop
        case "documents": self = .documents
        case "downloads": self = .downloads
        case "library" where inside.count > 2 && inside[1] == "containers": self = .container(spelled[2])
        case "library" where inside.count > 2 && inside[1] == "group containers": self = .groupContainer(spelled[2])
        case "library" where inside.count > 1 && inside[1] == "mobile documents": self = .iCloudDrive
        default: return nil
        }
    }
}
